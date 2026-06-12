# CLI Version of the Elm Compiler in Elm

<br>


## What Is It?

A version of the [port of the Elm compiler](https://github.com/pithub/elm-compiler-in-elm)
from Haskell to Elm that can be run in the command line using [Node.js](https://nodejs.org/).

The main purpose of this version is to be able to easily compare the output of the compiler port to
that of the original Haskell version, both the generated JavaScript code and the error messages.

The following commands are implemented:

- elmie init
- elmie install
- elmie make (without `--docs`)
- elmie repl

<br>


## How to Run It?


#### Compile the App

```sh
make build
```

or

```sh
elm make src/Main.elm --output elm.js
```

#### Run the App

To see the usage message, just execute

```sh
./elmie
```

_(The name is an acronym for "ELM In Elm".)_