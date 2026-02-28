# Hello World Example

A simple example demonstrating basic usage of the library.

## What You'll Learn

- How to add the library as a dependency
- How to import and use library functions
- How to run a Gleam application

## Running the Example

```bash
cd examples/hello_world
gleam deps download
gleam run -m hello_world
```

Expected output:
```
Hello, World!
Hello, Gleam!
Hello, Developer!
```

## Running Tests

```bash
gleam test
```

## Key Concepts

### Importing the Library

```gleam
import my_gleam_project
```

### Using Library Functions

```gleam
let greeting = my_gleam_project.hello("World")
// -> "Hello, World!"
```

## Code Walkthrough

The `src/hello_world.gleam` file:

1. Imports the library
2. Calls `my_gleam_project.hello()` with different names
3. Prints the results to the console

## Next Steps

- Explore the library's full API in the [documentation](../../README.md)
- Check the main library tests for more usage examples
