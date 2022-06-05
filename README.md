# Alpine V8
This Dockerfile builds Google's V8 library and tools on alpine. This project
is meant to be used in other multistage Dockerfiles to copy the V8 library and
include files over. At least that is what I am using it for.

# Usage
Include this image in your multistage Dockerfile and copy the V8 lib and
includes over. E.g.

```Dockerfile
FROM purpleworld/alpine-v8:latest as v8
FROM alpine:3.8
...
COPY --from=v8 /root/v8/include /usr/include
COPY --from=v8 /root/v8/lib /usr/lib
...
```
