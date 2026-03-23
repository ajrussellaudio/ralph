#!/bin/bash
# lib/functions.sh — Sourceable library: YAML front matter helpers and routing.
#
# Sourced by both ralph.sh (runtime) and bats tests.
# Global variables consumed by determine_mode():
#   RAW_LABEL      — feature label; empty string means "no label" mode
#   PLANS_DIR      — path to the plans/<label>/ directory
#   REPO           — GitHub owner/repo slug
#   FEATURE_BRANCH — e.g. feat/<label>

# ── YAML front matter helpers ──────────────────────────────────────────────────

# Reads a single YAML front matter field value from a .md file.
# Usage: get_front_matter_field <file> <field>
get_front_matter_field() {
  local file="$1" field="$2"
  python3 - "$file" "$field" <<'PYEOF'
import sys, re
file_path, field = sys.argv[1], sys.argv[2]
with open(file_path) as f:
    content = f.read()
m = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
if not m:
    sys.exit(0)
for line in m.group(1).splitlines():
    if re.match(r'^' + re.escape(field) + r'\s*:', line):
        val = line.split(':', 1)[1].strip().strip('"').strip("'")
        print(val, end='')
        break
PYEOF
}

# Overwrites a single YAML front matter field in a .md file without corrupting
# the rest of the file.
# Usage: set_front_matter_field <file> <field> <value>
set_front_matter_field() {
  local file="$1" field="$2" value="$3"
  python3 - "$file" "$field" "$value" <<'PYEOF'
import sys, re
file_path, field, value = sys.argv[1], sys.argv[2], sys.argv[3]
with open(file_path) as f:
    content = f.read()
m = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
if not m:
    sys.exit(1)
fm = m.group(1)
new_fm = re.sub(
    r'^(' + re.escape(field) + r'\s*:).*$',
    lambda _: field + ': ' + value,
    fm,
    flags=re.MULTILINE
)
if new_fm == fm:
    sys.stderr.write(f"Warning: field '{field}' not found in front matter\n")
    sys.exit(1)
new_content = '---\n' + new_fm + '\n---' + content[m.end():]
with open(file_path, 'w') as f:
    f.write(new_content)
PYEOF
}

# Appends a new | block scalar entry to the review_notes list in a .md task file.
# The review_notes field must be either `review_notes: []` or an existing list.
# Usage: append_review_note <file> <note_text>
append_review_note() {
  local file="$1" note="$2"
  python3 - "$file" "$note" <<'PYEOF'
import sys, re

file_path, new_note = sys.argv[1], sys.argv[2]
with open(file_path) as f:
    content = f.read()

fm_m = re.match(r'^---\n(.*?)\n---\n', content, re.DOTALL)
if not fm_m:
    sys.exit("No front matter found")

fm = fm_m.group(1)
rest = content[fm_m.end():]

# Parse existing | block scalar entries
existing = []
rn_match = re.search(r'(?m)^review_notes:(?:[^\n]*\n?)((?:[ \t]+[^\n]*\n?)*)', fm)
if rn_match:
    for em in re.finditer(r'[ \t]+-[ \t]+\|\n((?:(?:[ \t]{4}[^\n]*)?\n)*)', rn_match.group(0)):
        lines = [l[4:] if l.startswith('    ') else '' for l in em.group(1).splitlines()]
        existing.append('\n'.join(lines).rstrip())

# Remove existing review_notes block
fm = re.sub(r'(?m)^review_notes:(?:[^\n]*\n?)(?:[ \t]+[^\n]*\n?)*', '', fm)

# Append new entry
existing.append(new_note.strip())

# Build YAML list of | block scalars
entries_yaml = ''
for note in existing:
    entries_yaml += '  - |\n'
    for line in note.splitlines():
        entries_yaml += '    ' + line + '\n'

block = 'review_notes:\n' + entries_yaml
fm = fm.rstrip('\n') + '\n' + block + '\n'

with open(file_path, 'w') as f:
    f.write(f"---\n{fm}---\n{rest}")
PYEOF
}

# Returns the last entry in the review_notes list from a .md task file.
# Usage: get_last_review_note <file>
get_last_review_note() {
  local file="$1"
  python3 - "$file" <<'PYEOF'
import sys, re

file_path = sys.argv[1]
with open(file_path) as f:
    content = f.read()

fm_m = re.match(r'^---\n(.*?)\n---\n', content, re.DOTALL)
if not fm_m:
    sys.exit(0)
fm = fm_m.group(1)

notes = []
rn_match = re.search(r'(?m)^review_notes:(?:[^\n]*\n?)((?:[ \t]+[^\n]*\n?)*)', fm)
if rn_match:
    for em in re.finditer(r'[ \t]+-[ \t]+\|\n((?:(?:[ \t]{4}[^\n]*)?\n)*)', rn_match.group(0)):
        lines = [l[4:] if l.startswith('    ') else '' for l in em.group(1).splitlines()]
        notes.append('\n'.join(lines).rstrip())

if notes:
    print(notes[-1], end='')
PYEOF
}

# Returns all entries in the review_notes list, each prefixed with "[Review N]".
# Usage: get_all_review_notes <file>
get_all_review_notes() {
  local file="$1"
  python3 - "$file" <<'PYEOF'
import sys, re

file_path = sys.argv[1]
with open(file_path) as f:
    content = f.read()

fm_m = re.match(r'^---\n(.*?)\n---\n', content, re.DOTALL)
if not fm_m:
    sys.exit(0)
fm = fm_m.group(1)

notes = []
rn_match = re.search(r'(?m)^review_notes:(?:[^\n]*\n?)((?:[ \t]+[^\n]*\n?)*)', fm)
if rn_match:
    for em in re.finditer(r'[ \t]+-[ \t]+\|\n((?:(?:[ \t]{4}[^\n]*)?\n)*)', rn_match.group(0)):
        lines = [l[4:] if l.startswith('    ') else '' for l in em.group(1).splitlines()]
        notes.append('\n'.join(lines).rstrip())

for i, note in enumerate(notes, 1):
    print(f"[Review {i}]")
    for line in note.splitlines():
        print(f"  {line}")
    print()
PYEOF
}

# ── Routing ────────────────────────────────────────────────────────────────────

# Populates MODE, TASK_FILE, TASK_ID based on YAML front matter in task files.
# MODE is one of: implement | review | review-round2 | fix | force-approve | feature-pr | complete
determine_mode() {
  PR_NUMBER=""
  ISSUE_NUMBER=""
  TASK_FILE=""
  TASK_ID=""

  if [[ -z "$RAW_LABEL" ]]; then
    MODE="complete"
    echo "  ▶  Mode: $MODE  (no --label given)"
    return
  fi

  echo "  🔍 Scanning task files in ${PLANS_DIR}…"

  local routing
  if ! routing=$(python3 - "$PLANS_DIR" <<'PYEOF'
import sys, os, re, glob

plans_dir = sys.argv[1]

def parse_front_matter(path):
    with open(path) as f:
        content = f.read()
    m = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
    if not m:
        return {}
    fm = {}
    for line in m.group(1).splitlines():
        if ':' in line:
            k, _, v = line.partition(':')
            fm[k.strip()] = v.strip().strip('"').strip("'")
    return fm

files = sorted(glob.glob(os.path.join(plans_dir, '*.md')))
tasks = []
for f in files:
    fm = parse_front_matter(f)
    tid_m = re.match(r'^(\d+)', os.path.basename(f))
    if not tid_m:
        continue
    tasks.append({
        'file': f,
        'id': tid_m.group(1),
        'status': fm.get('status', 'pending'),
        'priority': fm.get('priority', 'normal'),
        'blocked_by': [int(x) for x in re.findall(r'\d+', fm.get('blocked_by', '[]'))],
        'branch': fm.get('branch', ''),
        'fix_count': int(fm.get('fix_count', '0') or '0'),
    })

if not tasks:
    print('complete\t\t')
    sys.exit(0)

status_map = {int(t['id']): t['status'] for t in tasks}

def deps_done(blocked_by):
    return all(status_map.get(dep) == 'done' for dep in blocked_by)

# Priority 1: needs_review — always route to review (branch read from front matter)
for t in tasks:
    if t['status'] == 'needs_review':
        print(f"review\t{t['file']}\t{t['id']}")
        sys.exit(0)

# Priority 2: needs_review_2 — force-approve if fix_count >= 2, else review-round2
for t in tasks:
    if t['status'] == 'needs_review_2':
        if t['fix_count'] >= 2:
            print(f"force-approve\t{t['file']}\t{t['id']}")
        else:
            print(f"review-round2\t{t['file']}\t{t['id']}")
        sys.exit(0)

# Priority 3: needs_fix — force-approve if fix_count >= 2, else fix
for t in tasks:
    if t['status'] == 'needs_fix':
        if t['fix_count'] >= 2:
            print(f"force-approve\t{t['file']}\t{t['id']}")
        else:
            print(f"fix\t{t['file']}\t{t['id']}")
        sys.exit(0)

# Priority 4: in_progress (resume interrupted work)
for t in tasks:
    if t['status'] == 'in_progress':
        print(f"fix\t{t['file']}\t{t['id']}")
        sys.exit(0)

# Priority 5: pending with all blocked_by deps done (high priority first)
ready = [t for t in tasks if t['status'] == 'pending' and deps_done(t['blocked_by'])]
high = [t for t in ready if t['priority'] == 'high']
if high:
    t = high[0]
    print(f"implement\t{t['file']}\t{t['id']}")
    sys.exit(0)
if ready:
    t = ready[0]
    print(f"implement\t{t['file']}\t{t['id']}")
    sys.exit(0)

# All done?
if all(t['status'] == 'done' for t in tasks):
    print('all-done\t\t')
    sys.exit(0)

# Otherwise (all remaining tasks are blocked)
print('blocked\t\t')
PYEOF
); then
    echo "Error: routing script failed — check task files in ${PLANS_DIR}"
    exit 1
  fi

  local mode task_file task_id
  IFS=$'\t' read -r mode task_file task_id <<< "$routing"

  if [[ "$mode" == "all-done" ]]; then
    local feature_pr_count
    feature_pr_count=$(gh pr list --repo "$REPO" --state open \
      --base "main" \
      --head "$FEATURE_BRANCH" \
      --json number --jq 'length' \
      < /dev/null 2>/dev/null || echo "1")
    if [[ "$feature_pr_count" == "0" ]]; then
      MODE="feature-pr"
      echo "  ▶  Mode: $MODE  (all tasks done, opening feat→main PR)"
    else
      MODE="complete"
      echo "  ▶  Mode: $MODE  (all tasks done, feature PR already open)"
    fi
  elif [[ "$mode" == "blocked" ]]; then
    MODE="blocked"
    echo "  ▶  Mode: blocked  (all remaining pending tasks are blocked)"
  else
    MODE="$mode"
    TASK_FILE="$task_file"
    TASK_ID="$task_id"
    if [[ "$MODE" == "complete" ]]; then
      echo "  ▶  Mode: $MODE  (no work to do)"
    else
      echo "  ▶  Mode: $MODE  (Task $TASK_ID)"
    fi
  fi
}

# Loads the mode file and substitutes all placeholders.
build_prompt() {
  local mode_file="$MODES_DIR/$MODE.md"
  if [[ ! -f "$mode_file" ]]; then
    echo "  ❌  Mode file not found: $mode_file"
    exit 1
  fi

  PROMPT=$(cat "$mode_file")
  PROMPT="${PROMPT//\{\{REPO\}\}/$REPO}"
  PROMPT="${PROMPT//\{\{PR_NUMBER\}\}/$PR_NUMBER}"
  PROMPT="${PROMPT//\{\{ISSUE_NUMBER\}\}/$ISSUE_NUMBER}"
  PROMPT="${PROMPT//\{\{BUILD_CMD\}\}/$BUILD_CMD}"
  PROMPT="${PROMPT//\{\{TEST_CMD\}\}/$TEST_CMD}"
  PROMPT="${PROMPT//\{\{FEATURE_BRANCH\}\}/$FEATURE_BRANCH}"
  PROMPT="${PROMPT//\{\{FEATURE_LABEL\}\}/$FEATURE_LABEL}"
  PROMPT="${PROMPT//\{\{TASK_FILE\}\}/$TASK_FILE}"
  PROMPT="${PROMPT//\{\{TASK_ID\}\}/$TASK_ID}"
  PROMPT="${PROMPT//\{\{PLANS_DIR\}\}/$PLANS_DIR}"

  # Populate {{PRD_OVERVIEW}} from plans/<label>.md — body only, front matter stripped.
  local prd_overview=""
  local prd_file="${GIT_ROOT}/plans/${RAW_LABEL}.md"
  if [[ -n "$RAW_LABEL" && -f "$prd_file" ]]; then
    prd_overview=$(python3 - "$prd_file" <<'PYEOF'
import sys, re
with open(sys.argv[1]) as f:
    content = f.read()
body = re.sub(r'^---\n.*?\n---\n?', '', content, count=1, flags=re.DOTALL).strip()
print(body)
PYEOF
)
  fi
  PROMPT="${PROMPT//\{\{PRD_OVERVIEW\}\}/$prd_overview}"
}
