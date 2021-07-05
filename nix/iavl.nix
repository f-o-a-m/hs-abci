{ stdenv, fetchFromGitHub, buildGoModule }:

buildGoModule rec {
  pname = "iavl";
  version = "0.12.4";

  src = fetchFromGitHub {
    owner = "tendermint";
    repo = pname;
    rev = "de73d47fa87401bd935dffe3eca93ddaf0e3e105";
    sha256 = "1phf9jacgh30n4vgm5grncmk1yn80x32l7gpnlbscimmizyhrdl5";
  };

  vendorSha256 = "1ra1v9x53f1rc9zsz42x0x5gqf7z5qccg71xp8prpjjzkzwh4cy1";
}
