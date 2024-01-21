# Zig Taskflow

Attempt at recreating https://github.com/cpp-taskflow/cpp-taskflow in Zig.

![build](https://github.com/mm318/zig_taskflow/actions/workflows/build.yml/badge.svg)


## Example:
```zig
fn func1(x: *const i32) struct { i32 } { return x.* + 1; }
fn func2(x: *const i32) struct { i32 } { return x.* - 2; }
fn func2(x: *const i32) struct { i32 } { return x.* + 3; }

const FlowTask = Task.createTaskType(
    &.{ i32 },
    &.{ i32 },
);
    
var flow = Flow.init(&allocator);
defer flow.free();

var a = try flow.newTask(FlowTask, .{ 1 }, &func1);
var b = try flow.newTask(FlowTask, .{ undefined }, &func2);
var c = try flow.newTask(FlowTask, .{ undefined }, &func3);

try flow.connect(a, 0, b, 0);
try flow.connect(b, 0, c, 0);

try flow.execute();
const result = c.getOutputPtr(0).*;
```

For a more complete example, see [main.zig](src/main.zig).


## Usage

### Installation
```bash
git clone https://github.com/mm318/zig_taskflow.git
```

### Build
All commands should be run from the `zig_taskflow` directory.

To build:
```bash
zig build
```

To run tests:
```bash
zig build -Doptimize=Debug test --summary all
zig build -Doptimize=ReleaseFast test --summary all
```

### Develop

To format the source code:
```bash
zig fmt .
```


## Requirements

Developed using Ubuntu 20.04 and Zig 0.11.0.  
