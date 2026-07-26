final: prev: {
  mongodb-ce-7_0 = prev.mongodb-ce.overrideAttrs (old: {
    version = "7.0.30";

    # Official MongoDB Community Edition binary distribution. This avoids
    # compiling MongoDB from source on every uncached nixpkgs revision.
    src = prev.fetchurl {
      url = "https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu2204-7.0.30.tgz";
      hash = "sha256-Km64VqSBqLykdgGhrWLSalit8ZmfGgI1ld5C+U+QDSo=";
    };

    meta = old.meta // {
      changelog = "https://www.mongodb.com/docs/manual/release-notes/7.0/";
    };
  });
}
