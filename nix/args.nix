# Shared derivations passed to the other module files as arguments.
#
# This file deliberately contains only `_module.args` and no `options`/`config`
# keys: the module system rejects a top-level `_module` in any file that also
# declares those, and putting it inside `config` would make the argument
# unavailable while the modules that take it are still being evaluated.
{ pkgs, ... }:

{
  # wf-recorder 0.6.0 doesn't build against ffmpeg's default (9.0): it reads
  # AVCodec.sample_fmts, a field removed upstream. Pin ffmpeg_6 until
  # wf-recorder is patched for the new API. Shared so packages.nix (which
  # installs it) and scripts.nix (which calls it) use one identical build.
  _module.args.wf-recorder = pkgs.wf-recorder.override { ffmpeg = pkgs.ffmpeg_6; };
}
