# maelstrom-zig-node

Zig node framework for building distributed systems for learning for
https://github.com/jepsen-io/maelstrom and solving https://fly.io/dist-sys/
challenges.

# What is Maelstrom?

Maelstrom is a platform for learning distributed systems. It is build around Jepsen and Elle to ensure no properties are
violated. With maelstrom you build nodes that form distributed system that can process different workloads.

# Features

- zig 0.10.1 + mt
- simple API
- response types auto-deduction, extra data available via Value()
- unknown message types handling
- TODO: a/sync RPC() support + timeout / context
- TODO: lin/seq/lww kv storage

# Examples

## Echo workload

```bash
$ cargo build --examples
$ zig build && ~/Projects/maelstrom/maelstrom test -w echo --bin ./zig-out/bin/echo --node-count 1 --time-limit 10 --log-stderr
````

implementation:

...

spec:

receiving

    {
      "src": "c1",
      "dest": "n1",
      "body": {
        "type": "echo",
        "msg_id": 1,
        "echo": "Please echo 35"
      }
    }

send back the same msg with body.type == echo_ok.

    {
      "src": "n1",
      "dest": "c1",
      "body": {
        "type": "echo_ok",
        "msg_id": 1,
        "in_reply_to": 1,
        "echo": "Please echo 35"
      }
    }

## Broadcast workload

```bash
$ cargo build --examples
$ RUST_LOG=debug maelstrom test -w broadcast --bin ./target/debug/examples/broadcast --node-count 2 --time-limit 20 --rate 10 --log-stderr
````

implementation:

...

## lin-kv workload

```bash
$ cargo build --examples
$ RUST_LOG=debug ~/Projects/maelstrom/maelstrom test -w lin-kv --bin ./target/debug/examples/lin_kv --node-count 4 --concurrency 2n --time-limit 10 --rate 100 --log-stderr
````

implementation:

...

## g-set workload

```bash
$ cargo build --examples
$ RUST_LOG=debug ~/Projects/maelstrom/maelstrom test -w g-set --bin ./target/debug/examples/g_set --node-count 2 --concurrency 2n --time-limit 20 --rate 10 --log-stderr
```

implementation:

```
...
```

# API

## Key-Value storage

```
...
```

## RPC

```
...
```

## Requests

```
...
```

## Responses

```
...
```

# Why

Now its a good time to learn Zig. Zig is beautiful C-like language.
That Will be not perfect but ok. Thanks TigerBeetle for the inspiration.

Thanks Aphyr and guys a lot.

# Where

[GitHub](https://github.com/sitano/maelstrom-zig-node)

# Links

- https://zig.news/xq/zig-build-explained-part-3-1ima
- https://zig.news/mattnite/import-and-packages-23mb 
- https://ziglearn.org/chapter-1/
- https://ziglang.org/learn/
- https://ziglang.org/learn/samples/
- https://ziglang.org/documentation/master/