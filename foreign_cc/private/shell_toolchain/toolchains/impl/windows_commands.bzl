# buildifier: disable=module-docstring
load("@rules_foreign_cc//foreign_cc/private/shell_toolchain/toolchains:function_and_call.bzl", "FunctionAndCall")

_REPLACE_VALUE = "\\${EXT_BUILD_DEPS}"

def os_name():
    return "windows"

def pwd():
    return "$(type -t cygpath > /dev/null && cygpath $(pwd) -w || pwd -W)"

def echo(text):
    return "echo \"{text}\"".format(text = text)

def export_var(name, value):
    return "export {name}={value}".format(name = name, value = value)

def local_var(name, value):
    return "local {name}={value}".format(name = name, value = value)

def use_var(name):
    return "$" + name

def env():
    return "env"

def path(expression):
    return "export PATH=\"{expression}:$PATH\"".format(expression = expression)

def touch(path):
    return "touch " + path

def mkdirs(path):
    return "mkdir -p " + path

def if_else(condition, if_text, else_text):
    return """\
if [ {condition} ]; then
  {if_text}
else
  {else_text}
fi
""".format(condition = condition, if_text = if_text, else_text = else_text)

# buildifier: disable=function-docstring
def define_function(name, text):
    lines = []
    lines.append("function " + name + "() {")
    for line_ in text.splitlines():
        lines.append("  " + line_)
    lines.append("}")
    return "\n".join(lines)

def replace_in_files(dir, from_, to_):
    return FunctionAndCall(
        text = """\
if [ -d "$1" ]; then
  $REAL_FIND -L $1 -type f   \\( -name "*.pc" -or -name "*.la" -or -name "*-config" -or -name "*.cmake" \\)   -exec sed -i 's@'"$2"'@'"$3"'@g' {} ';'
fi
""",
    )

def copy_dir_contents_to_dir(source, target):
    return """cp -L -r --no-target-directory "{source}" "{target}" && find {target} -type f -exec touch -r "{source}" "{{}}" \\;""".format(
        source = source,
        target = target,
    )

def symlink_contents_to_dir(source, target):
    text = """\
local target="$2"
mkdir -p "$target"
if [[ -f "$1" ]]; then
  ##symlink_to_dir## "$1" "$target"
elif [[ -L "$1" ]]; then
  local actual=$(readlink "$1")
  ##symlink_contents_to_dir## "$actual" "$target"
elif [[ -d "$1" ]]; then
  SAVEIFS=$IFS
  IFS=$'\n'
  local children=($($REAL_FIND -H "$1" -maxdepth 1 -mindepth 1))
  IFS=$SAVEIFS
  for child in "${children[@]}"; do
    ##symlink_to_dir## "$child" "$target"
  done
fi
"""
    return FunctionAndCall(text = text)

def symlink_to_dir(source, target):
    text = """\
local target="$2"
mkdir -p "$target"
if [[ -f "$1" ]]; then
  ln -s -f -t "$target" "$1"
elif [[ -L "$1" ]]; then
  local actual=$(readlink "$1")
  ##symlink_to_dir## "$actual" "$target"
elif [[ -d "$1" ]]; then
  SAVEIFS=$IFS
  IFS=$'\n'
  local children=($($REAL_FIND -H "$1" -maxdepth 1 -mindepth 1))
  IFS=$SAVEIFS
  local dirname=$(basename "$1")
  for child in "${children[@]}"; do
    if [[ "$dirname" != *.ext_build_deps ]]; then
      ##symlink_to_dir## "$child" "$target/$dirname"
    fi
  done
else
  echo "Can not copy $1"
fi
"""
    return FunctionAndCall(text = text)

def script_prelude():
    return """\
set -euo pipefail
if [ -f /usr/bin/find ]; then
  REAL_FIND="/usr/bin/find"
else
  REAL_FIND="$(which find)"
fi
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"
export SYSTEMDRIVE="C:"
"""

def increment_pkg_config_path(source):
    text = """\
local children=$($REAL_FIND $1 -mindepth 1 -name '*.pc')
# assume there is only one directory with pkg config
for child in $children; do
  export PKG_CONFIG_PATH="$${PKG_CONFIG_PATH:-}$$:$(dirname $child)"
  return
done
"""
    return FunctionAndCall(text = text)

def cat(filepath):
    return "cat \"{}\"".format(filepath)

def redirect_out_err(from_process, to_file):
    return from_process + " &> " + to_file

def assert_script_errors():
    return "set -e"

def cleanup_function(on_success, on_failure):
    text = "\n".join([
        "local ecode=$?",
        "if [ $ecode -eq 0 ]; then",
        on_success,
        "else",
        on_failure,
        "fi",
    ])
    return FunctionAndCall(text = text, call = "trap \"cleanup_function\" EXIT")

def children_to_path(dir_):
    text = """\
if [ -d {dir_} ]; then
  local tools=$($REAL_FIND $EXT_BUILD_DEPS/bin -maxdepth 1 -mindepth 1)
  for tool in $tools;
  do
    if  [[ -d \"$tool\" ]] || [[ -L \"$tool\" ]]; then
      export PATH=$PATH:$tool
    fi
  done
fi""".format(dir_ = dir_)
    return FunctionAndCall(text = text)

def define_absolute_paths(dir_, abs_path):
    return "##replace_in_files## {dir_} {REPLACE_VALUE} {abs_path}".format(
        dir_ = dir_,
        REPLACE_VALUE = _REPLACE_VALUE,
        abs_path = abs_path,
    )

def replace_absolute_paths(dir_, abs_path):
    return "##replace_in_files## {dir_} {abs_path} {REPLACE_VALUE}".format(
        dir_ = dir_,
        REPLACE_VALUE = _REPLACE_VALUE,
        abs_path = abs_path,
    )
