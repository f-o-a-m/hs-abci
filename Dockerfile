FROM haskell:8-stretch

RUN apt-get update && apt-get install --assume-yes protobuf-compiler libsecp256k1-dev libtinfo-dev

COPY stack.yaml /tmp/stack.resolver-dummy.yaml
RUN stack --resolver `cat /tmp/stack.resolver-dummy.yaml | grep resolver | sed 's/resolver://'` setup && stack exec -- ghc --version

# Install GHC.
WORKDIR /project
COPY . /project

# Install project to /usr/local/bin
RUN stack build --copy-bins --local-bin-path /usr/local/bin

