# buildifier: disable=module-docstring
load(":cc_toolchain_util.bzl", "absolutize_path_in_str")
load(":framework.bzl", "get_foreign_cc_dep")
load(":make_script.bzl", "pkgconfig_script")

# buildifier: disable=function-docstring
def create_configure_script(
        workspace_name,
        target_os,
        tools,
        flags,
        root,
        user_options,
        user_vars,
        is_debug,
        configure_command,
        deps,
        inputs,
        configure_in_place,
        autoconf,
        autoconf_options,
        autoconf_env_vars,
        autoreconf,
        autoreconf_options,
        autoreconf_env_vars,
        autogen,
        autogen_command,
        autogen_options,
        autogen_env_vars,
        make_commands):
    env_vars_string = _get_env_vars(workspace_name, tools, flags, user_vars, deps, inputs)

    ext_build_dirs = inputs.ext_build_dirs

    script = pkgconfig_script(ext_build_dirs)

    root_path = "$$EXT_BUILD_ROOT$$/{}".format(root)
    configure_path = "{}/{}".format(root_path, configure_command)
    if configure_in_place:
        script.append("##symlink_contents_to_dir## $$EXT_BUILD_ROOT$$/{} $$BUILD_TMPDIR$$".format(root))
        root_path = "$$BUILD_TMPDIR$$"
        configure_path = "{}/{}".format(root_path, configure_command)

    if autogen and configure_in_place:
        # NOCONFIGURE is pseudo standard and tells the script to not invoke configure.
        # We explicitly invoke configure later.
        autogen_env_vars = _get_autogen_env_vars(autogen_env_vars)
        script.append('{} "{}/{}" {}'.format(
            " ".join(['{}="{}"'.format(key, autogen_env_vars[key]) for key in autogen_env_vars]),
            root_path,
            autogen_command,
            " ".join(autogen_options),
        ).lstrip())

    if autoconf and configure_in_place:
        script.append("{} autoconf {}".format(
            " ".join(["{}=\"{}\"".format(key, autoconf_env_vars[key]) for key in autoconf_env_vars]),
            " ".join(autoconf_options),
        ).lstrip())

    if autoreconf and configure_in_place:
        script.append("{} autoreconf {}".format(
            " ".join(['{}="{}"'.format(key, autoreconf_env_vars[key]) for key in autoreconf_env_vars]),
            " ".join(autoreconf_options),
        ).lstrip())

    script.append('{env_vars} "{configure}" --prefix=$$BUILD_TMPDIR$$/$$INSTALL_PREFIX$$ {user_options}'.format(
        env_vars = env_vars_string,
        configure = configure_path,
        user_options = " ".join(user_options),
    ))

    script.append("set -x")
    script.extend(make_commands)
    script.append("set +x")

    return script

def _get_autogen_env_vars(autogen_env_vars):
    # Make a copy if necessary so we can set NOCONFIGURE.
    if autogen_env_vars.get("NOCONFIGURE"):
        return autogen_env_vars
    vars = {}
    for key in autogen_env_vars:
        vars[key] = autogen_env_vars.get(key)
    vars["NOCONFIGURE"] = "1"
    return vars

# buildifier: disable=function-docstring
def _get_env_vars(
        workspace_name,
        tools,
        flags,
        user_vars,
        deps,
        inputs):
    vars = _get_configure_variables(workspace_name, tools, flags, user_vars)
    deps_flags = _define_deps_flags(deps, inputs)

    if "LDFLAGS" in vars.keys():
        vars["LDFLAGS"] = vars["LDFLAGS"] + deps_flags.libs
    else:
        vars["LDFLAGS"] = deps_flags.libs

    # -I flags should be put into preprocessor flags, CPPFLAGS
    # https://www.gnu.org/software/autoconf/manual/autoconf-2.63/html_node/Preset-Output-Variables.html
    vars["CPPFLAGS"] = deps_flags.flags

    return " ".join(["{}=\"{}\""
        .format(key, _join_flags_list(workspace_name, vars[key])) for key in vars])

def _define_deps_flags(deps, inputs):
    # It is very important to keep the order for the linker => put them into list
    lib_dirs = []

    # Here go libraries built with Bazel
    gen_dirs_set = {}
    for lib in inputs.libs:
        dir_ = lib.dirname
        if not gen_dirs_set.get(dir_):
            gen_dirs_set[dir_] = 1
            lib_dirs.append("-L$$EXT_BUILD_ROOT$$/" + dir_)

    include_dirs_set = {}
    for include_dir in inputs.include_dirs:
        include_dirs_set[include_dir] = "-I$$EXT_BUILD_ROOT$$/" + include_dir
    for header in inputs.headers:
        include_dir = header.dirname
        if not include_dirs_set.get(include_dir):
            include_dirs_set[include_dir] = "-I$$EXT_BUILD_ROOT$$/" + include_dir
    include_dirs = include_dirs_set.values()

    # For the external libraries, we need to refer to the places where
    # we copied the dependencies ($EXT_BUILD_DEPS/<lib_name>), because
    # we also want configure to find that same files with pkg-config
    # -config or other mechanics.
    # Since we need the names of include and lib directories under
    # the $EXT_BUILD_DEPS/<lib_name>, we ask the provider.
    gen_dirs_set = {}
    for dep in deps:
        external_deps = get_foreign_cc_dep(dep)
        if external_deps:
            for artifact in external_deps.artifacts.to_list():
                if not gen_dirs_set.get(artifact.gen_dir):
                    gen_dirs_set[artifact.gen_dir] = 1

                    dir_name = artifact.gen_dir.basename
                    include_dirs.append("-I$$EXT_BUILD_DEPS$$/{}/{}".format(dir_name, artifact.include_dir_name))
                    lib_dirs.append("-L$$EXT_BUILD_DEPS$$/{}/{}".format(dir_name, artifact.lib_dir_name))

    return struct(
        libs = lib_dirs,
        flags = include_dirs,
    )

# See https://www.gnu.org/software/make/manual/html_node/Implicit-Variables.html
_CONFIGURE_FLAGS = {
    "ARFLAGS": "cxx_linker_static",
    "ASFLAGS": "assemble",
    "CFLAGS": "cc",
    "CXXFLAGS": "cxx",
    "LDFLAGS": "cxx_linker_executable",
    # missing: cxx_linker_shared
}

_CONFIGURE_TOOLS = {
    "AR": "cxx_linker_static",
    "CC": "cc",
    "CXX": "cxx",
    # missing: cxx_linker_executable
}

def _get_configure_variables(workspace_name, tools, flags, user_env_vars):
    vars = {}

    for flag in _CONFIGURE_FLAGS:
        flag_value = getattr(flags, _CONFIGURE_FLAGS[flag])
        if flag_value:
            vars[flag] = flag_value

    # Merge flags lists
    for user_var in user_env_vars:
        toolchain_val = vars.get(user_var)
        if toolchain_val:
            vars[user_var] = toolchain_val + [user_env_vars[user_var]]

    tools_dict = {}
    for tool in _CONFIGURE_TOOLS:
        tool_value = getattr(tools, _CONFIGURE_TOOLS[tool])
        if tool_value:
            # Force absolutize of tool paths, which may relative to the workspace
            # dir (hermetic toolchains) be provided in project repositories
            # (i.e hermetic toolchains).
            tools_dict[tool] = [_absolutize(workspace_name, tool_value, True)]

    # Replace tools paths if user passed other values
    for user_var in user_env_vars:
        toolchain_val = tools_dict.get(user_var)
        if toolchain_val:
            tools_dict[user_var] = [user_env_vars[user_var]]

    vars.update(tools_dict)

    # Put all other environment variables, passed by the user
    for user_var in user_env_vars:
        if not vars.get(user_var):
            vars[user_var] = [user_env_vars[user_var]]

    return vars

def _absolutize(workspace_name, text, force = False):
    return absolutize_path_in_str(workspace_name, "$$EXT_BUILD_ROOT$$/", text, force)

def _join_flags_list(workspace_name, flags):
    return " ".join([_absolutize(workspace_name, flag) for flag in flags])
