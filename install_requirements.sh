#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update
sudo apt-get install -y \
  libudunits2-dev \
  default-jdk \
  libproj-dev \
  libgdal-dev \
  cmake \
  git
