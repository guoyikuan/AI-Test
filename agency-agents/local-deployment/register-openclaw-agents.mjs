#!/usr/bin/env node
import { access, chmod, cp, lstat, mkdir, readdir, readFile, rename, stat, writeFile } from "node:fs/promises";
import crypto from "node:crypto";
import os from "node:os";
import path from "node:path";

const scriptDir = path.dirname(new URL(import.meta.url).pathname);
const scriptPath = path.join(scriptDir, "register-openclaw-agents.mjs");
const defaultManifestPath = path.join(scriptDir, "installation-manifest.json");

const envHome = process.env.OPENCLAW_HOME || os.homedir();

const args = process.argv.slice(2);

const opts = {
  mode: "apply",
  manifestPath: process.env.OPENCLAW_MANIFEST_PATH || defaultManifestPath,
  workspaceRoot: process.env.OPENCLAW_WORKSPACE_ROOT || path.join(envHome, ".openclaw", "agency-agents"),
  configPath: process.env.OPENCLAW_CONFIG_PATH || path.join(envHome, ".openclaw", "openclaw.json"),
  agentRoot: process.env.OPENCLAW_AGENT_ROOT || path.join(envHome, ".openclaw", "agents"),
  backupRoot: process.env.OPENCLAW_BACKUP_ROOT || path.join(envHome, ".openclaw", "backups"),
  expectedGovernanceHash: process.env.OPENCLAW_EXPECTED_GOVERNANCE_HASH || "",
  signaturePath: "",
};

const usage = () => {
  console.log(`
Usage:
  node register-openclaw-agents.mjs [options]

Options:
  --verify-only                  Validate workspaces and manifest only (no writes)
  --manifest <path>              Manifest path (default: local-deployment/installation-manifest.json)
  --workspace-root <path>
  --config-path <path>
  --agent-root <path>
  --backup-root <path>
  --expected-governance-hash <hash>
  --signature <path>             Required for apply mode (signed entrypoint contract)
`);
};

for (let i = 0; i < args.length; i += 1) {
  const arg = args[i];
  switch (arg) {
    case "--verify-only":
      opts.mode = "verify-only";
      break;
    case "--manifest":
      opts.manifestPath = args[++i];
      break;
    case "--workspace-root":
      opts.workspaceRoot = args[++i];
      break;
    case "--config-path":
      opts.configPath = args[++i];
      break;
    case "--agent-root":
      opts.agentRoot = args[++i];
      break;
    case "--backup-root":
      opts.backupRoot = args[++i];
      break;
    case "--expected-governance-hash":
      opts.expectedGovernanceHash = args[++i] || "";
      break;
    case "--signature":
      opts.signaturePath = args[++i] || "";
      break;
    case "-h":
    case "--help":
      usage();
      process.exit(0);
    default:
      throw new Error(`Unknown option: ${arg}`);
  }
}

const safeName = (value) => /^[a-z0-9][a-z0-9-]*$/.test(value);
const withAbsolute = (value, label) => {
  if (!path.isAbsolute(value)) {
    throw new Error(`${label} must be absolute: ${value}`);
  }
  return path.normalize(value);
};

const readJson = async (filePath) => {
  const raw = await readFile(filePath, "utf8");
  return JSON.parse(raw);
};

const computeSha256 = (input) => crypto.createHash("sha256").update(input).digest("hex");

const noSymlink = async (target, label, allowMissing = false) => {
  try {
    const stats = await lstat(target);
    if (stats.isSymbolicLink()) {
      throw new Error(`${label} is symlink: ${target}`);
    }
    return stats;
  } catch (error) {
    if (allowMissing && error.code === "ENOENT") {
      return null;
    }
    throw error;
  }
};

const collectWorkspaceIds = async (workspaceRoot) => {
  const entries = await readdir(workspaceRoot, { withFileTypes: true, encoding: "utf8" });
  const ids = [];

  for (const entry of entries) {
    if (!entry.isDirectory()) {
      continue;
    }

    if (!safeName(entry.name)) {
      throw new Error(`Invalid workspace name: ${entry.name}`);
    }

    const workspaceDir = path.join(workspaceRoot, entry.name);
    const stats = await lstat(workspaceDir);
    if (stats.isSymbolicLink()) {
      throw new Error(`Workspace path is symlink: ${workspaceDir}`);
    }

    const requiredFiles = ["SOUL.md", "AGENTS.md", "IDENTITY.md"];
    for (const required of requiredFiles) {
      const file = path.join(workspaceDir, required);
      await access(file);
      const fs = await lstat(file);
      if (fs.isSymbolicLink()) {
        throw new Error(`Workspace required file is symlink: ${file}`);
      }
    }

    ids.push(entry.name);
  }

  ids.sort();
  return ids;
};

const walkWorkspaceFiles = async (baseDir, root = baseDir) => {
  const fileInfos = [];

  const walk = async (current) => {
    const entries = await readdir(current, { withFileTypes: true, encoding: "utf8" });
    for (const entry of entries) {
      const full = path.join(current, entry.name);
      const stats = await lstat(full);
      if (stats.isSymbolicLink()) {
        throw new Error(`Symlink found in workspace: ${full}`);
      }
      if (stats.isDirectory()) {
        await walk(full);
      } else if (stats.isFile()) {
        fileInfos.push({
          rel: path.relative(root, full),
          size: stats.size,
          full,
        });
      }
    }
  };

  await walk(baseDir);
  return fileInfos.sort((a, b) => (a.rel < b.rel ? -1 : a.rel > b.rel ? 1 : 0));
};

const computeWorkspaceHash = async (workspaceRoot) => {
  const entries = await walkWorkspaceFiles(workspaceRoot);
  const hasher = crypto.createHash("sha256");
  for (const file of entries) {
    hasher.update(file.rel);
    hasher.update("|");
    hasher.update(String(file.size));
    hasher.update("\0");
    const content = await readFile(file.full);
    hasher.update(content);
  }
  return hasher.digest("hex");
};

const verifySignature = async (payload) => {
  if (!opts.signaturePath) {
    throw new Error("Missing governance signature: apply mode must be invoked from install-all-local gate");
  }
  const raw = await readFile(opts.signaturePath, "utf8");
  const signature = JSON.parse(raw);
  const expectedKeys = ["entrypoint", "issuedAt", "manifestDigest", "backupRoot", "payloadDigest", "workflow", "token"];
  for (const key of expectedKeys) {
    if (!signature[key]) {
      throw new Error(`Invalid governance signature: missing ${key}`);
    }
  }

  if (signature.workflow !== "local-install-gov") {
    throw new Error(`Invalid governance signature workflow: ${signature.workflow}`);
  }

  if (!signature.entrypoint.endsWith("local-deployment/install-all-local.sh")) {
    throw new Error(`Invalid governance signature entrypoint: ${signature.entrypoint}`);
  }

  const expected = computePayloadDigest(payload);
  if (signature.payloadDigest !== expected) {
    throw new Error("Invalid governance signature payload digest");
  }
};

const computePayloadDigest = ({ manifestPath, workspaceHash, backupRoot, token }) => {
  const canonical = [
    manifestPath,
    workspaceHash,
    backupRoot,
    token,
  ].join("\n");
  return computeSha256(canonical);
};

const normalizePathList = async () => {
  opts.manifestPath = withAbsolute(path.resolve(opts.manifestPath), "Manifest path");
  opts.workspaceRoot = withAbsolute(path.resolve(opts.workspaceRoot), "Workspace root");
  opts.configPath = withAbsolute(path.resolve(opts.configPath), "Config path");
  opts.agentRoot = withAbsolute(path.resolve(opts.agentRoot), "Agent root");
  opts.backupRoot = withAbsolute(path.resolve(opts.backupRoot), "Backup root");
};

const loadManifest = async () => {
  const manifest = await readJson(opts.manifestPath);
  if (!manifest || typeof manifest !== "object") {
    throw new Error("Manifest payload is invalid");
  }
  if (!manifest.schema) {
    throw new Error("Manifest must define schema");
  }
  return manifest;
};

const validateEnvironment = async () => {
  const workspaceStats = await noSymlink(opts.workspaceRoot, "Workspace root");
  if (!workspaceStats.isDirectory()) {
    throw new Error(`Workspace root is not a directory: ${opts.workspaceRoot}`);
  }

  if (opts.mode === "apply") {
    await noSymlink(opts.agentRoot, "Agent root");
    await noSymlink(opts.backupRoot, "Backup root", true);
  }

  try {
    await stat(opts.configPath);
  } catch (error) {
    throw new Error(`Config path not found: ${opts.configPath}`);
  }

  if (opts.mode === "apply") {
    const agentDirParent = path.dirname(opts.agentRoot);
    await noSymlink(agentDirParent, "Agent parent");
  }
};

const applyRegistration = async (manifest, workspaceIds, governanceHash) => {
  const config = await readJson(opts.configPath);
  if (!config?.agents || !Array.isArray(config.agents.list)) {
    throw new Error("OpenClaw config does not contain agents.list");
  }

  const existing = new Map();
  for (const item of config.agents.list) {
    if (item && typeof item.id === "string") {
      existing.set(item.id, item);
    }
  }

  const normalizedBackupRoot = opts.backupRoot;
  await mkdir(normalizedBackupRoot, { recursive: true });
  const configStat = await stat(opts.configPath);
  const backupPath = path.join(
    normalizedBackupRoot,
    `openclaw.json.before-agency-agents-${Date.now()}`,
  );

  const added = [];
  for (const agentId of workspaceIds) {
    if (existing.has(agentId)) {
      continue;
    }
    const workspace = path.join(opts.workspaceRoot, agentId);
    const agentDir = path.join(opts.agentRoot, agentId, "agent");
    await mkdir(agentDir, { recursive: true, mode: 0o700 });
    added.push({ id: agentId, workspace, agentDir });
  }

  // No partial coverage: stage all mutations before writing.
  const staged = {
    ...config,
    agents: {
      ...config.agents,
      list: [
        ...config.agents.list,
        ...added,
      ],
    },
    governance: {
      ...config.governance,
      schema: "agency-agents.openclaw-governance/v1",
      lastGovernanceHash: governanceHash,
      lastManifest: path.basename(opts.manifestPath),
      lastUpdated: new Date().toISOString(),
    },
  };

  const tempConfig = `${opts.configPath}.agency-agents-${process.pid}.tmp`;

  await cp(opts.configPath, backupPath);
  await writeFile(tempConfig, `${JSON.stringify(staged, null, 2)}\n`, { mode: configStat.mode & 0o777 });
  await chmod(tempConfig, configStat.mode & 0o777);
  await rename(tempConfig, opts.configPath);

  return {
    schema: "agency-agents.openclaw-registration/v1",
    workspaceCount: workspaceIds.length,
    added: added.length,
    configuredCount: staged.agents.list.length,
    backupPath,
    governanceHash,
  };
};

const printSummary = (summary) => {
  console.log(JSON.stringify(summary));
};

const main = async () => {
  try {
    await normalizePathList();
    await validateEnvironment();

    const manifest = await loadManifest();
    const workspaceIds = await collectWorkspaceIds(opts.workspaceRoot);
    if (workspaceIds.length === 0) {
      throw new Error("integrations/openclaw contains no workspace directories");
    }

    const workspaceHash = await computeWorkspaceHash(opts.workspaceRoot);
    const manifestHash =
      typeof opts.expectedGovernanceHash === "string" && opts.expectedGovernanceHash.length > 0
        ? opts.expectedGovernanceHash
        : manifest.governanceHash;

    if (manifestHash && manifestHash !== workspaceHash) {
      throw new Error(`Governance hash mismatch: manifest=${manifestHash} actual=${workspaceHash}`);
    }

    if (opts.mode === "verify-only") {
      printSummary({
        schema: "agency-agents.openclaw-registration/v1",
        workspaceCount: workspaceIds.length,
        verified: true,
        manifest: path.basename(opts.manifestPath),
        governanceHash: workspaceHash,
        backupRoot: opts.backupRoot,
      });
      return;
    }

    const payload = {
      manifestPath: opts.manifestPath,
      workspaceHash,
      backupRoot: opts.backupRoot,
      token: process.env.OPENCLAW_GOVERNANCE_TOKEN || manifest.governanceToken || "agent-install",
    };

    await verifySignature(payload);

    const summary = await applyRegistration(manifest, workspaceIds, workspaceHash);
    printSummary(summary);
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
};

await main();
