# Building V8 for alpine is a real pain. We have to compile from source, because it has to be
# linked against musl, and we also have to recompile some of the build tools as the official
# build workflow tends to assume glibc by including vendored tools that link against it.
#
# The general strategy is this:
#
#   1. Build GN for alpine (this is a build dependency) 
#   2. Use depot_tools to fetch the V8 source and dependencies (needs glibc)
#   3. Build V8 for alpine
#   4. Make warez
#

#
# STEP 1
# Build GN for alpine
#
FROM alpine:latest as gn-builder

# This is the GN commit that we want to build. Most commits will probably build just fine but
# this happened to be the latest commit when I did this.
ARG GN_COMMIT=37baefb026b199605affa7bcb24810d1724ce373

RUN apk update \
    apk upgrade
RUN apk add --no-cache --virtual .gyp python3 make g++
RUN ln -sf python3 /usr/bin/python
RUN apk add tini
RUN apk add clang
RUN apk add curl
RUN apk add git
RUN apk add ninja
RUN apk add tar
RUN apk add xz
RUN git clone https://gn.googlesource.com/gn
RUN python gn/build/gen.py
RUN ninja -C gn/out
RUN cp -f gn/out/gn /usr/local/bin/gn
#
# STEP 2
# Use depot_tools to fetch the V8 source and dependencies
#
# The depot_tools scripts have a hard dependency on glibc (or at least a soft one that I didn't
# bother figuring out). Fortunately we only need it to actually download the source and its dependencies
# so we can do this in a place with glibc, and then pass the results on to an alpine builder.
#
FROM debian as source

RUN set -x
RUN apt-get update
RUN apt-get upgrade
RUN apt-get install -y git
RUN apt-get install -y curl
RUN apt-get install -y python3
RUN apt-get install -y xz-utils
RUN ln -sf python3 /usr/bin/python
  # Clone depot_tools
RUN git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git /tmp/depot_tools && \
PATH=$PATH:/tmp/depot_tools
  # fetch V8
RUN cd /tmp && /tmp/depot_tools/fetch v8
RUN cd /tmp/v8 && /tmp/depot_tools/gclient sync
#
# STEP 3
# Build V8 for alpine
#
FROM alpine:latest as v8

COPY --from=source /tmp/v8 /tmp/v8
COPY --from=gn-builder /usr/local/bin/gn /tmp/v8/buildtools/linux64/gn

RUN apk update \
    apk upgrade
RUN \
  apk add --update --no-cache curl \
    g++ \
    gcc \
    glib-dev \
    icu-dev \
    libstdc++ \
    linux-headers \
    make \
    ninja \
    python3 \
    tar \
    xz
RUN ln -sf python3 /usr/bin/python
RUN cd /tmp/v8 && \
  /tmp/v8/tools/dev/v8gen.py x64.release -- \
    binutils_path=\"/usr/bin\" \
    target_os=\"linux\" \
    target_cpu=\"x64\" \
    v8_target_cpu=\"x64\" \
    v8_enable_future=true \
    is_official_build=true \
    is_component_build=false \
    is_cfi=false \
    is_clang=false \
    use_custom_libcxx=false \
    use_sysroot=false \
    use_gold=false \
    use_allocator_shim=false \
    treat_warnings_as_errors=false \
    symbol_level=0 \
    strip_debug_info=true \
    v8_use_external_startup_data=false \
    v8_enable_i18n_support=false \
    v8_enable_gdbjit=false \
    v8_static_library=true \
    v8_experimental_extra_library_files=[] \
    v8_extra_library_files=[]
  # Build V8
RUN cd /tmp/v8 && ninja -C out.gn/x64.release -j $(getconf _NPROCESSORS_ONLN)
  # Brag
RUN find /tmp/v8/out.gn/x64.release -name '*.a'
#
# STEP 4
# Provide slim image with V8
#
FROM alpine:latest
COPY --from=v8 /tmp/v8/include /root/v8/include
COPY --from=v8 /tmp/v8/out.gn/x64.release/obj /root/v8/lib