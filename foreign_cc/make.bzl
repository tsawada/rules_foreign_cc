# buildifier: disable=module-docstring
load(
    "//foreign_cc/private:cc_toolchain_util.bzl",
    "get_flags_info",
    "get_tools_info",
)
load(
    "//foreign_cc/private:detect_root.bzl",
    "detect_root",
)
load(
    "//foreign_cc/private:framework.bzl",
    "CC_EXTERNAL_RULE_ATTRIBUTES",
    "CC_EXTERNAL_RULE_FRAGMENTS",
    "cc_external_rule_impl",
    "create_attrs",
)
load("//foreign_cc/private:make_script.bzl", "create_make_script")
load("//toolchains/native_tools:tool_access.bzl", "get_make_data")

def _make(ctx):
    make_data = get_make_data(ctx)

    tools_deps = ctx.attr.tools_deps + make_data.deps

    attrs = create_attrs(
        ctx.attr,
        configure_name = "GNUMake",
        create_configure_script = _create_make_script,
        tools_deps = tools_deps,
        make_path = make_data.path,
    )
    return cc_external_rule_impl(ctx, attrs)

def _create_make_script(configureParameters):
    ctx = configureParameters.ctx
    attrs = configureParameters.attrs
    inputs = configureParameters.inputs

    root = detect_root(ctx.attr.lib_source)

    tools = get_tools_info(ctx)
    flags = get_flags_info(ctx)

    data = ctx.attr.data or list()

    # Generate a list of arguments for make
    args = " ".join([
        ctx.expand_location(arg, data)
        for arg in ctx.attr.args
    ])

    make_commands = []
    for target in ctx.attr.targets:
        make_commands.append("{make} -C $$EXT_BUILD_ROOT$$/{root} {target} {args}".format(
            make = attrs.make_path,
            root = root,
            args = args,
            target = target,
        ))

    return create_make_script(
        root = root,
        inputs = inputs,
        make_commands = make_commands,
    )

def _attrs():
    attrs = dict(CC_EXTERNAL_RULE_ATTRIBUTES)
    attrs.pop("make_commands")
    attrs.update({
        "args": attr.string_list(
            doc = "A list of arguments to pass to the call to `make`",
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

make = rule(
    doc = (
        "Rule for building external libraries with GNU Make. " +
        "GNU Make commands (make and make install by default) are invoked with prefix=\"install\" " +
        "(by default), and other environment variables for compilation and linking, taken from Bazel C/C++ " +
        "toolchain and passed dependencies."
    ),
    attrs = _attrs(),
    fragments = CC_EXTERNAL_RULE_FRAGMENTS,
    output_to_genfiles = True,
    implementation = _make,
    toolchains = [
        "@rules_foreign_cc//toolchains:make_toolchain",
        "@rules_foreign_cc//foreign_cc/private/shell_toolchain/toolchains:shell_commands",
        "@bazel_tools//tools/cpp:toolchain_type",
    ],
    # TODO: Remove once https://github.com/bazelbuild/bazel/issues/11584 is closed and the min supported
    # version is updated to a release of Bazel containing the new default for this setting.
    incompatible_use_toolchain_transition = True,
)
