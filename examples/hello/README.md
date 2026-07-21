# Hello Dram

This is a separate Ard project that consumes Dram through a local path dependency.

```sh
ard run examples/hello/main.ard
curl -i http://127.0.0.1:8080/
curl -i -X POST --data 'hello' http://127.0.0.1:8080/echo
curl -i -X POST --data 'too large' http://127.0.0.1:8080/echo
```

The server binds to `127.0.0.1` unless `host` is passed explicitly to `listen`. This example lowers the body limit to eight bytes, so the final request returns 413.
