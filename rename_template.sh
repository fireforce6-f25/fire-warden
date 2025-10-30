#!/usr/bin/env bash
# rename_template.sh
# Replace occurrences of 'template' -> newname and 'Template' -> NewTitle
# Infers names from repository folder and ignores .fuseki

set -euo pipefail
IFS=$'\n\t'

usage() {
  cat <<EOF
Usage: $0 [options]

This script infers the replacement names from the repository directory name.
If your repo folder is named like: "my-project-name" then:
  newname = my-project-name
  NewTitle = "My Project Name"

It replaces all occurrences of the lowercase word 'template' with newname
and the capitalized word 'Template' with NewTitle in tracked files and
file/directory names under the repository root. It skips the .fuseki folder.

Options:
  --dry-run    Show what would change, don't modify files
  --all        Include all files in the working tree (not only tracked)
  --yes        Don't prompt; apply changes
  -h, --help   Show this help

Notes:
- The script operates on files tracked by git by default. Use --all to include other files.
- Binary files are skipped.
- This is a best-effort tool; review changes before committing.
EOF
}

# parse args
DRY_RUN=false
ASSUME_YES=false
INCLUDE_ALL=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true; shift;;
    --all)
      INCLUDE_ALL=true; shift;;
    --yes)
      ASSUME_YES=true; shift;;
    -h|--help)
      usage; exit 0;;
    --)
      shift; break;;
    -*|--*)
      echo "Unknown option: $1"; usage; exit 2;;
    *)
      echo "Unexpected positional argument: $1"; usage; exit 2;;
  esac
done

# derive NEWNAME and NEWTITLE from the repository folder name
if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "This script must be run inside a git repository." >&2
  exit 1
fi
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

repo_dir_basename=$(basename "$REPO_ROOT")
# expected format: lower-case words separated by hyphens
NEWNAME="$repo_dir_basename"

# create NewTitle: replace hyphens with spaces and capitalize first letter of every word
# Example: "my-project-name" -> "My Project Name"
# Acronym handling: if a word matches a known acronym it will be fully uppercased.
# You can customize the list via the environment variable ACRONYM_LIST (comma-separated, lower-case)
# Default list includes common acronyms like ai, api, http, xml, json, sql, id, ip
ACRONYM_LIST=${ACRONYM_LIST:-"ai,api,http,https,xml,json,sql,id,ip"}
## NOTE: This means the script will replace the capitalized token 'Template' with a
## space-separated title when replacing content and filenames. Filenames will thus
## contain spaces if the repository name has hyphens (git supports filenames with
## spaces, but be aware of shell escaping when working with them).
NEWTITLE=$(printf "%s" "$repo_dir_basename" | awk -F- -v acrlist="$ACRONYM_LIST" '
  BEGIN {
    n=split(acrlist, a, ",");
    for(i=1;i<=n;i++){ acr[tolower(a[i])]=1 }
  }
  {
    out="";
    for(i=1;i<=NF;i++){
      w=$i;
      lw=tolower(w);
      if(length(w)>0){
        if(lw in acr){
          w = toupper(w);
        } else {
          w = toupper(substr(w,1,1)) substr(w,2);
        }
        out = out (i==1?"":" ") w;
      }
    }
    print out
  }'
)
OLDLOW="template"
OLDCAP="Template"

echo "Repository root: $REPO_ROOT"
echo "Inferred NEWNAME: '$NEWNAME'"
echo "Inferred NEWTITLE: '$NEWTITLE'"
echo "Replacing '$OLDLOW' -> '$NEWNAME' and '$OLDCAP' -> '$NEWTITLE'"
if [ "$DRY_RUN" = true ]; then
  echo "DRY RUN: no files will be modified"
fi

# helper: is file binary? use git attributes or file command
is_binary() {
  local file="$1"
  if command -v file >/dev/null 2>&1; then
    file --brief --mime-encoding "$file" | grep -q binary && return 0 || return 1
  fi
  return 1
}

# collect files to process
FILES=()
if [ "$INCLUDE_ALL" = true ]; then
  # include all files in the working tree except .git and .fuseki
  while IFS= read -r _f; do
    p=${_f#./}
    case "$p" in
      .git/*|.git|.fuseki|.fuseki/*) continue;;
    esac
    FILES+=("$p")
  done < <(find . -type f -print)
else
  # include tracked files
  while IFS= read -r _f; do
    case "$_f" in
      .fuseki|.fuseki/*) continue;;
    esac
    FILES+=("$_f")
  done < <(git ls-files)

  # also include untracked (but not ignored) files
  while IFS= read -r _f; do
    # avoid duplicates
    skip=false
    for existing in "${FILES[@]}"; do
      if [ "$existing" = "$_f" ]; then
        skip=true; break
      fi
    done
    case "$_f" in
      .fuseki|.fuseki/*) skip=true;;
    esac
    if [ "$skip" = false ]; then
      FILES+=("$_f")
    fi
  done < <(git ls-files --others --exclude-standard)
fi

# Exclude this script itself from processing
script_invoked="$0"
script_rel="${script_invoked#./}"
script_basename="$(basename "$script_invoked")"
EXCLUDE_FILES=("$script_invoked" "$script_rel" "$script_basename")
if [[ "$script_invoked" = /* ]]; then
  case "$script_invoked" in
    "$REPO_ROOT"/*)
      EXCLUDE_FILES+=("${script_invoked#"$REPO_ROOT"/}")
      ;;
  esac
fi
if [ ${#EXCLUDE_FILES[@]} -gt 0 ]; then
  filtered_files=()
  for _f in "${FILES[@]}"; do
    skip=false
    for ex in "${EXCLUDE_FILES[@]}"; do
      if [ "$_f" = "$ex" ]; then
        skip=true; break
      fi
    done
    if [ "$skip" = false ]; then
      filtered_files+=("$_f")
    fi
  done
  FILES=("${filtered_files[@]}")
fi

# 1) Show files that would change in contents
changed_content=()
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  case "$f" in
    .fuseki|.fuseki/*) continue;;
  esac
  if is_binary "$f"; then
    continue
  fi
  if grep -q -- "$OLDLOW" "$f" || grep -q -- "$OLDCAP" "$f"; then
    changed_content+=("$f")
  fi
done

# 2) Find files and dirs with names containing the tokens
rename_targets=()
for f in "${FILES[@]}"; do
  case "$f" in
    .fuseki|.fuseki/*) continue;;
  esac
  if [[ "$f" == *$OLDLOW* ]] || [[ "$f" == *$OLDCAP* ]]; then
    rename_targets+=("$f")
  fi
done

# also check directories in the repo tree (to handle directory names that include template/Template)
DIRS=()
while IFS= read -r _d; do
  d=${_d#./}
  case "$d" in
    .fuseki|.fuseki/*) continue;;
  esac
  DIRS+=("$d")
done < <(find . -type d -print | sed 's|^\./||' | sort -r)
for d in "${DIRS[@]}"; do
  [ -z "$d" ] && continue
  case "$d" in
    .fuseki|.fuseki/*) continue;;
  esac
  if [[ "$d" == *$OLDLOW* ]] || [[ "$d" == *$OLDCAP* ]]; then
    rename_targets+=("$d")
  fi
done

# report
if [ ${#changed_content[@]} -eq 0 ] && [ ${#rename_targets[@]} -eq 0 ]; then
  echo "No matches for '$OLDLOW' or '$OLDCAP' in tracked files or paths. Nothing to do."
  exit 0
fi

if [ ${#changed_content[@]} -gt 0 ]; then
  echo
  echo "Files with content matches:"
  for f in "${changed_content[@]}"; do
    echo "  $f"
  done
fi

if [ ${#rename_targets[@]} -gt 0 ]; then
  echo
  echo "Files/dirs with matching names (to be renamed):"
  printf "%s\n" "${rename_targets[@]}" | sort -u | sed 's/^/  /g'
fi

if [ "$DRY_RUN" = true ]; then
  echo
  echo "Dry-run complete. No changes were made."
  exit 0
fi

# confirm
if [ "$ASSUME_YES" = false ]; then
  read -r -p "Proceed with these changes? [y/N] " ans
  case "$ans" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Aborting."; exit 0;;
  esac
fi

# 3) Replace contents
for f in "${changed_content[@]}"; do
  tmpfile=$(mktemp)
  perl -pe "s/\Q$OLDLOW\E/$NEWNAME/g; s/\Q$OLDCAP\E/$NEWTITLE/g;" "$f" > "$tmpfile"
  if ! cmp -s "$f" "$tmpfile"; then
    mv "$tmpfile" "$f"
    echo "Updated content: $f"
  else
    rm -f "$tmpfile"
  fi
done

# 4) Rename files and directories
IFS=$'\n'
unique_targets=($(printf "%s\n" "${rename_targets[@]}" | sort -u | awk '{print length($0) " " $0}' | sort -rn | cut -d' ' -f2-))
for path in "${unique_targets[@]}"; do
  [ -e "$path" ] || continue
  case "$path" in
    .fuseki|.fuseki/*) continue;;
  esac
  newpath="$path"
  newpath=${newpath//$OLDLOW/$NEWNAME}
  newpath=${newpath//$OLDCAP/$NEWTITLE}
  if [ "$newpath" != "$path" ]; then
    newdir=$(dirname "$newpath")
    if [ ! -d "$newdir" ]; then
      mkdir -p "$newdir"
    fi
    git mv -f -- "$path" "$newpath" || mv -f -- "$path" "$newpath"
    echo "Renamed: $path -> $newpath"
  fi
done

# 5) Cleanup: remove empty directories named 'template' or 'Template'
echo
echo "Cleaning up empty '$OLDLOW'/'$OLDCAP' directories..."
for name in "$OLDLOW" "$OLDCAP"; do
  while IFS= read -r d; do
    d=${d#./}
    [ -z "$d" ] && continue
    case "$d" in
      .git|.git/*) continue;;
      .fuseki|.fuseki/*) continue;;
    esac
    if [ -d "$d" ] && [ -z "$(ls -A "$d")" ]; then
      if rmdir -- "$d" 2>/dev/null; then
        echo "Removed empty directory: $d"
      fi
    fi
  done < <(find . -type d -name "$name" -print | sed 's|^\./||' | sort -r)
done

echo "All done. Review changes with 'git status' and 'git diff'."
