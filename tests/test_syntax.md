# Syntax Highlighting Test

This is a markdown file to test code block highlighting in the Folx editor.

## Nim Code Block

```nim
proc greetUser(name: string): string =
  ## Greets a user with the given name
  let greeting = "Hello, " & name & "!"
  echo greeting
  return greeting

type
  User* = object
    name*: string
    age*: int
    isActive*: bool

var users: seq[User] = @[]
let newUser = User(name: "Alice", age: 30, isActive: true)
users.add(newUser)
```

## Python Code Block

```python
def calculate_fibonacci(n):
    """Calculate the nth Fibonacci number."""
    if n <= 1:
        return n
    
    a, b = 0, 1
    for i in range(2, n + 1):
        a, b = b, a + b
    
    return b

# Example usage
numbers = [calculate_fibonacci(i) for i in range(10)]
print(f"First 10 Fibonacci numbers: {numbers}")
```

## JavaScript Code Block

```javascript
class TaskManager {
    constructor() {
        this.tasks = [];
        this.nextId = 1;
    }
    
    addTask(description) {
        const task = {
            id: this.nextId++,
            description: description,
            completed: false,
            createdAt: new Date()
        };
        this.tasks.push(task);
        return task;
    }
    
    completeTask(id) {
        const task = this.tasks.find(t => t.id === id);
        if (task) {
            task.completed = true;
        }
    }
}

const manager = new TaskManager();
manager.addTask("Test syntax highlighting");
```

## Bash/Shell Code Block

```bash
#!/bin/bash

# Script to build and run the Folx editor
echo "Building Folx editor..."

if nim c src/main.nim; then
    echo "Build successful!"
    
    # Check if markdown file exists
    if [[ -f "test_syntax.md" ]]; then
        echo "Running editor with test file..."
        ./src/main test_syntax.md
    else
        echo "Test file not found, running editor normally..."
        ./src/main
    fi
else
    echo "Build failed!"
    exit 1
fi
```

## Indented Code Block

Regular text, followed by an indented code block:

    # This is an indented code block
    def simple_function():
        x = 42
        y = "Hello World"
        return x + len(y)
    
    result = simple_function()
    print(f"Result: {result}")

## Mixed Content

Here's some regular markdown text with `inline code` segments.

```rust
fn main() {
    let greeting = "Hello, Rust!";
    println!("{}", greeting);
    
    let numbers: Vec<i32> = (1..=5).collect();
    for num in &numbers {
        println!("Number: {}", num);
    }
}
```

More text here.

## Edge Cases

Empty code block:
```nim
```

Code block with just whitespace:
```python
    
    
```

Unclosed code block:
```nim
proc test() =
  echo "This block is not closed"

This should be treated as regular markdown text.