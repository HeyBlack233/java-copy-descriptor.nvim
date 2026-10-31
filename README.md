# java-copy-descriptor.nvim

An extension for [`nvim-jdtls`](https://github.com/mfussenegger/nvim-jdtls) that copies the JVM method descriptor of the Java method or constructor under the cursor.

Place the cursor on a method name and run:

```vim
:JavaCopyDescriptor
```

The command resolves the declaring class, parameter types, and return type through JDT LS, converts them to a JVM descriptor, and writes the descriptor to the system clipboard (`+` register).

Example:

```java
public String plain(String text, Map<String, List<Long>> map) {
    return text;
}
```

With the cursor on `plain`, the command copies:

```text
(Ljava/lang/String;Ljava/util/Map;)Ljava/lang/String;
```

The success message also includes the resolved member, for example:

```text
JavaCopyDescriptor: copied demo.Foo#plain (Ljava/lang/String;Ljava/util/Map;)Ljava/lang/String;
```

## Features

- Works on method declarations and method calls.
- Resolves overloads through JDT LS call hierarchy and constructor references.
- Supports project source, binary/Gradle dependencies, JDK types, private methods, static methods, and interface methods.
- Supports constructors, including overloaded constructors, implicit default constructors, record compact constructors, enum constructors, and non-static inner-class constructors.
- Erases generics, resolves bounded and unbounded type variables, converts varargs and multidimensional arrays, and emits nested classes as `Outer$Inner`.
- Uses the current buffer contents, so descriptors follow unsaved edits.
- Does not modify the project or buffers.

## Requirements

- Neovim 0.11 or newer (tested with 0.12.5).
- [`nvim-jdtls`](https://github.com/mfussenegger/nvim-jdtls).
- Eclipse JDT LS attached to the current Java buffer.
- The `tree-sitter-java` parser. With `nvim-treesitter`, install it with `:TSInstall java`.
- A writable `+` register, normally provided by a clipboard provider.

JDT LS must be started with class file content support. `nvim-jdtls` enables this by default.

## Installation

### lazy.nvim

```lua
{
  'HeyBlack233/java-copy-descriptor.nvim',
  dependencies = { 'mfussenegger/nvim-jdtls' },
  config = function()
    require('java-copy-descriptor').setup()
  end,
}
```

### Native packages

```lua
vim.opt.rtp:prepend('/path/to/java-copy-descriptor.nvim')
```

The plugin has no key mappings and registers only `:JavaCopyDescriptor`.

## Configuration

`setup()` is optional:

```lua
require('java-copy-descriptor').setup({
  client_name = 'jdtls',
  clipboard_register = '+',
  notify = true,
})
```

| Option | Default | Description |
| --- | --- | --- |
| `client_name` | `"jdtls"` | LSP client name to use. |
| `clipboard_register` | `"+"` | Register that receives the descriptor. |
| `notify` | `true` | Show success and error notifications. |

## API

```lua
require('java-copy-descriptor').setup(opts)
require('java-copy-descriptor').copy()
require('java-copy-descriptor').descriptor_at_cursor(function(err, descriptor, metadata)
  -- descriptor is the JVM descriptor string
  -- metadata contains owner, name, kind, and uri when available
end)
```

`descriptor_at_cursor` is asynchronous and does not write to the clipboard. It is useful in tests and custom mappings.

## How it works

1. `textDocument/prepareCallHierarchy` identifies the exact method or constructor at the cursor.
2. The declaration is loaded from the current buffer, from its source file, or from JDT LS `java/classFileContents` for binary dependencies.
3. A tree-sitter Java parse locates the declaration and its type nodes.
4. Type nodes are resolved with `textDocument/hover` and `textDocument/definition`; the definition URI gives the package and nested-class context needed for binary names.
5. Generic types are erased to their raw type, and type variables are replaced by their first bound or `java.lang.Object`.
6. Constructors at call sites are selected by querying `textDocument/references` for each direct constructor of the declared class.
7. The descriptor is written to the clipboard and verified.

## Supported descriptor cases

- Primitives and `void`.
- Reference types and nested types (`java.util.Map$Entry`).
- Arrays and multidimensional arrays.
- Varargs.
- Generic erasure.
- Bounded and unbounded type variables.
- Constructors and overloaded constructors.
- Enum constructors, record compact constructors, and non-static inner-class constructors.
- Private, static, and interface methods.

## Limitations

- The command is only available in Java buffers with an attached `jdtls` client.
- Method references such as `Foo::new` are supported only when JDT LS resolves them through call hierarchy.
- Anonymous and local class constructors are not guaranteed to have a discoverable declaration.
- If JDT LS cannot resolve a type, the command reports an error instead of copying a partial or incorrect descriptor.
- Binary method resolution depends on JDT LS class file content support. If it is disabled, dependency methods cannot be inspected.

## Troubleshooting

- **No jdtls client**: wait for the project to import or check your `nvim-jdtls` configuration.
- **Tree-sitter parser missing**: run `:TSInstall java` and restart Neovim.
- **Could not resolve Java type**: ensure the project imports successfully and dependencies are on the JDT LS classpath.
- **Register not writable**: configure a clipboard provider or choose another register in `setup({ clipboard_register = ... })`.
- **Wrong descriptor after editing**: make sure JDT LS has received the buffer change; the plugin reads the current buffer text locally, but type resolution still uses JDT LS.

## Development

```sh
./tests/run.sh
```

The test suite builds a small fixture project and a local dependency jar, then runs unit tests and headless JDT LS integration tests. Tests that need `jdtls` or `javac` are skipped with a message when those tools are unavailable.

## License

MIT. See [LICENSE](LICENSE).
