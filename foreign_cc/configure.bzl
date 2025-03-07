# buildifier: disable=module-docstring
load(
    "//foreign_cc/private:cc_toolchain_util.bzl",
    "get_flags_info",
    "get_tools_info",
    "is_debug_mode",
)
load("//foreign_cc/private:configure_script.bzl", "create_configure_script")
load("//foreign_cc/private:detect_root.bzl", "detect_root")
load(
    "//foreign_cc/private:framework.bzl",
    "CC_EXTERNAL_RULE_ATTRIBUTES",
    "CC_EXTERNAL_RULE_FRAGMENTS",
    "cc_external_rule_impl",
    "create_attrs",
)
load("//foreign_cc/private:shell_script_helper.bzl", "os_name")
load("//toolchains/native_tools:tool_access.bzl", "get_make_data")

def _configure_make(ctx):
    make_data = get_make_data(ctx)

    tools_deps = ctx.attr.tools_deps + make_data.deps

    copy_results = "##copy_dir_contents_to_dir## $$BUILD_TMPDIR$$/$$INSTALL_PREFIX$$ $$INSTALLDIR$$\n"

    attrs = create_attrs(
        ctx.attr,
        configure_name = "Configure",
        create_configure_script = _create_configure_script,
        postfix_script = copy_results + "\n" + ctx.attr.postfix_script,
        tools_deps = tools_deps,
        make_path = make_data.path,
    )
    return cc_external_rule_impl(ctx, attrs)

def _create_configure_script(configureParameters):
    ctx = configureParameters.ctx
    attrs = configureParameters.attrs
    inputs = configureParameters.inputs

    root = detect_root(ctx.attr.lib_source)
    install_prefix = _get_install_prefix(ctx)

    tools = get_tools_info(ctx)
    flags = get_flags_info(ctx)

    define_install_prefix = ["export INSTALL_PREFIX=\"" + _get_install_prefix(ctx) + "\""]

    data = ctx.attr.data or list()

    # Generate a list of arguments for make
    args = " ".join([
        ctx.expand_location(arg, data)
        for arg in ctx.attr.args
    ])

    make_commands = []

    if not ctx.attr.make_commands:
        for target in ctx.attr.targets:
            make_commands.append("{make} -C $$EXT_BUILD_ROOT$$/{root} {target} {args}".format(
                make = attrs.make_path,
                root = root,
                args = args,
                target = target,
            ))

    configure = create_configure_script(
        workspace_name = ctx.workspace_name,
        # as default, pass execution OS as target OS
        target_os = os_name(ctx),
        tools = tools,
        flags = flags,
        root = root,
        user_options = ctx.attr.configure_options,
        user_vars = dict(ctx.attr.configure_env_vars),
        is_debug = is_debug_mode(ctx),
        configure_command = ctx.attr.configure_command,
        deps = ctx.attr.deps,
        inputs = inputs,
        configure_in_place = ctx.attr.configure_in_place,
        autoconf = ctx.attr.autoconf,
        autoconf_options = ctx.attr.autoconf_options,
        autoconf_env_vars = ctx.attr.autoconf_env_vars,
        autoreconf = ctx.attr.autoreconf,
        autoreconf_options = ctx.attr.autoreconf_options,
        autoreconf_env_vars = ctx.attr.autoreconf_env_vars,
        autogen = ctx.attr.autogen,
        autogen_command = ctx.attr.autogen_command,
        autogen_options = ctx.attr.autogen_options,
        autogen_env_vars = ctx.attr.autogen_env_vars,
        make_commands = make_commands,
    )
    return define_install_prefix + configure

def _get_install_prefix(ctx):
    if ctx.attr.install_prefix:
        return ctx.attr.install_prefix
    if ctx.attr.lib_name:
        return ctx.attr.lib_name
    return ctx.attr.name

def _attrs():
    attrs = dict(CC_EXTERNAL_RULE_ATTRIBUTES)
    attrs.update({
        "args": attr.string_list(
            doc = "A list of arguments to pass to the call to `make`",
        ),
        "autoconf": attr.bool(
            mandatory = False,
            default = False,
            doc = (
                "Set to True if 'autoconf' should be invoked before 'configure', " +
                "currently requires 'configure_in_place' to be True."
            ),
        ),
        "autoconf_env_vars": attr.string_dict(
            doc = "Environment variables to be set for 'autoconf' invocation.",
        ),
        "autoconf_options": attr.string_list(
            doc = "Any options to be put in the 'autoconf.sh' command line.",
        ),
        "autogen": attr.bool(
            doc = (
                "Set to True if 'autogen.sh' should be invoked before 'configure', " +
                "currently requires 'configure_in_place' to be True."
            ),
            mandatory = False,
            default = False,
        ),
        "autogen_command": attr.string(
            doc = (
                "The name of the autogen script file, default: autogen.sh. " +
                "Many projects use autogen.sh however the Autotools FAQ recommends bootstrap " +
                "so we provide this option to support that."
            ),
            default = "autogen.sh",
        ),
        "autogen_env_vars": attr.string_dict(
            doc = "Environment variables to be set for 'autogen' invocation.",
        ),
        "autogen_options": attr.string_list(
            doc = "Any options to be put in the 'autogen.sh' command line.",
        ),
        "autoreconf": attr.bool(
            doc = (
                "Set to True if 'autoreconf' should be invoked before 'configure.', " +
                "currently requires 'configure_in_place' to be True."
            ),
            mandatory = False,
            default = False,
        ),
        "autoreconf_env_vars": attr.string_dict(
            doc = "Environment variables to be set for 'autoreconf' invocation.",
        ),
        "autoreconf_options": attr.string_list(
            doc = "Any options to be put in the 'autoreconf.sh' command line.",
        ),
        "configure_command": attr.string(
            doc = (
                "The name of the configuration script file, default: configure. " +
                "The file must be in the root of the source directory."
            ),
            default = "configure",
        ),
        "configure_env_vars": attr.string_dict(
            doc = "Environment variables to be set for the 'configure' invocation.",
        ),
        "configure_in_place": attr.bool(
            doc = (
                "Set to True if 'configure' should be invoked in place, i.e. from its enclosing " +
                "directory."
            ),
            mandatory = False,
            default = False,
        ),
        "configure_options": attr.string_list(
            doc = "Any options to be put on the 'configure' command line.",
        ),
        "install_prefix": attr.string(
            doc = (
                "Install prefix, i.e. relative path to where to install the result of the build. " +
                "Passed to the 'configure' script with --prefix flag."
            ),
            mandatory = False,
        ),
        "targets": attr.string_list(
            doc = (
                "A list of targets within the foreign build system to produce. An empty string (`\"\"`) will result in " +
                "a call to the underlying build system with no explicit target set"
            ),
            mandatory = False,
            default = ["", "install"],
        ),
    })

    return attrs

configure_make = rule(
    doc = (
        "Rule for building external libraries with configure-make pattern. " +
        "Some 'configure' script is invoked with --prefix=install (by default), " +
        "and other parameters for compilation and linking, taken from Bazel C/C++ " +
        "toolchain and passed dependencies. " +
        "After configuration, GNU Make is called."
    ),
    attrs = _attrs(),
    fragments = CC_EXTERNAL_RULE_FRAGMENTS,
    output_to_genfiles = True,
    implementation = _configure_make,
    toolchains = [
        "@rules_foreign_cc//toolchains:make_toolchain",
        "@rules_foreign_cc//foreign_cc/private/shell_toolchain/toolchains:shell_commands",
        "@bazel_tools//tools/cpp:toolchain_type",
    ],
    # TODO: Remove once https://github.com/bazelbuild/bazel/issues/11584 is closed and the min supported
    # version is updated to a release of Bazel containing the new default for this setting.
    incompatible_use_toolchain_transition = True,
)
