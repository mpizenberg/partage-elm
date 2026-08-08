# Deny Sharp install script

## Progress

- Increment 1 complete: `sharp` is explicitly denied; a clean frozen relay install skipped its script, and the production build, 106 relay Node tests, and 39 relay Worker tests pass.

## Goal

Explicitly deny the transitive `sharp` install script in the relay package and prove that the project does not depend on Miniflare's local image-processing support.

## Increments

1. Set `sharp: false`, remove the relay installation, perform a frozen reinstall, and verify the production build plus both relay test suites. Record whether Sharp's install script remains suppressed, then commit.

## Decisions

- Deny Sharp's install script rather than approving Miniflare's complete dependency setup. Alternative: retain `sharp: true`. Reason: the relay does not configure Miniflare's Images plugin, and clean installation and both relay runtimes pass without the script. Reversible by changing one boolean.
