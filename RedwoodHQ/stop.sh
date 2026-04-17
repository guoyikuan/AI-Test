tail app.pid | xargs kill
pgrep mongo | xargs kill
echo "RedwoodHQ stopped"
