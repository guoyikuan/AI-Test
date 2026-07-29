import { access, chmod, copyFile, mkdir, readFile, readdir, rename, stat, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

const homeDir = os.homedir();
const configPath = path.join(homeDir, ".openclaw", "openclaw.json");
const workspaceRoot = path.join(homeDir, ".openclaw", "agency-agents");
const agentRoot = path.join(homeDir, ".openclaw", "agents");
const backupRoot = path.join(homeDir, ".openclaw", "backups");

const configStat = await stat(configPath);
const config = JSON.parse(await readFile(configPath, "utf8"));

if (!config.agents || !Array.isArray(config.agents.list)) {
  throw new Error("OpenClaw config does not contain agents.list");
}

const entries = await readdir(workspaceRoot, { withFileTypes: true });
const agentIds = entries
  .filter((entry) => entry.isDirectory())
  .map((entry) => entry.name)
  .sort();

for (const agentId of agentIds) {
  if (!/^[a-z0-9][a-z0-9-]*$/.test(agentId)) {
    throw new Error(`Unsafe OpenClaw agent id: ${agentId}`);
  }
  const workspace = path.join(workspaceRoot, agentId);
  for (const requiredFile of ["SOUL.md", "AGENTS.md", "IDENTITY.md"]) {
    await access(path.join(workspace, requiredFile));
  }
}

const existingIds = new Set(config.agents.list.map((agent) => agent.id));
let added = 0;

for (const agentId of agentIds) {
  const workspace = path.join(workspaceRoot, agentId);
  const agentDir = path.join(agentRoot, agentId, "agent");
  await mkdir(agentDir, { recursive: true, mode: 0o700 });
  if (!existingIds.has(agentId)) {
    config.agents.list.push({
      id: agentId,
      name: agentId,
      workspace,
      agentDir,
    });
    existingIds.add(agentId);
    added += 1;
  }
}

await mkdir(backupRoot, { recursive: true, mode: 0o700 });
const backupPath = path.join(
  backupRoot,
  `openclaw.json.before-agency-agents-${Date.now()}`,
);
await copyFile(configPath, backupPath);
await chmod(backupPath, 0o600);

const temporaryPath = `${configPath}.agency-agents-${process.pid}.tmp`;
await writeFile(temporaryPath, `${JSON.stringify(config, null, 2)}\n`, {
  mode: configStat.mode & 0o777,
});
await chmod(temporaryPath, configStat.mode & 0o777);
await rename(temporaryPath, configPath);

console.log(JSON.stringify({
  schema: "agency-agents.openclaw-registration/v1",
  workspaceCount: agentIds.length,
  added,
  configuredCount: config.agents.list.length,
  backupPath,
}));
