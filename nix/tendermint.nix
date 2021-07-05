{ stdenv, fetchFromGitHub, buildGoModule }:

buildGoModule rec {
  pname = "tendermint";
  version = "0.32.8";

  src = fetchFromGitHub {
    owner = "tendermint";
    repo = pname;
    rev = "v${version}";
    sha256 = "1bk9hb8whvlvxn8ijrp7rg6m83wxj4ipp5v36yr47ibqirbngh5s";
  };

  vendorSha256 = "1vhd3s6yxfhirgipxcy0rh8sk55cdzirr8n8r31sijgyak92mq0l";
}
