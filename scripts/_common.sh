# Shared setup for scripts/*.sh. Source it after `cd` to the repository root.
# The app name is defined once, in project.yml (CLAUDE.md); read it from there.
APP_NAME="${APP_NAME:-$(sed -n 's/^name:[[:space:]]*//p' project.yml | head -n 1)}"
if [ -z "$APP_NAME" ]; then
  echo "could not read the app name from project.yml" >&2
  exit 1
fi
