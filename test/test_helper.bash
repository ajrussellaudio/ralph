# test/test_helper.bash — shared setup helpers for Ralph bats tests

RALPH_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# Create a minimal SQLite DB with the Ralph schema.
create_test_db() {
  local db_path="$1"
  sqlite3 "$db_path" <<'SQL'
CREATE TABLE IF NOT EXISTS prd (
  label    TEXT PRIMARY KEY,
  overview TEXT
);
CREATE TABLE IF NOT EXISTS tasks (
  id           INTEGER PRIMARY KEY,
  title        TEXT,
  body         TEXT,
  priority     TEXT    DEFAULT 'normal',
  status       TEXT    DEFAULT 'pending',
  branch       TEXT,
  review_notes TEXT,
  fix_count    INTEGER DEFAULT 0,
  blocked_by   INTEGER REFERENCES tasks(id)
);
SQL
}

# Insert a task row. Args: db_path id status [priority] [fix_count] [blocked_by]
insert_task() {
  local db_path="$1"
  local id="$2"
  local status="${3:-pending}"
  local priority="${4:-normal}"
  local fix_count="${5:-0}"
  local blocked_by="${6:-NULL}"
  sqlite3 "$db_path" \
    "INSERT INTO tasks (id, title, status, priority, fix_count, blocked_by)
     VALUES ($id, 'Task $id', '$status', '$priority', $fix_count, $blocked_by);"
}
