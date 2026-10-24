# Vendored dependencies

All required Solidity dependencies are ordinary source files in `lib/`; no installation, network access, submodules, or package manager is needed for build or tests.

OpenZeppelin Contracts supplies the ERC-20 implementation (only its transitive dependencies are included, with its MIT license). forge-std supplies test utilities (all Solidity files under its `src/`, with both upstream licenses). Upstream source files are unmodified.

```text
OpenZeppelin/openzeppelin-contracts v5.1.0
URL: https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.1.0
Archive SHA-256: 8a3b08cfc756437ba3343901565b18182adb42ec1e621960240a19da5d738686
Vendored files: 6

foundry-rs/forge-std v1.9.7
URL: https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7
Archive SHA-256: 45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94
Vendored files: 30
```
