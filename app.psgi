#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;

use lib "$FindBin::RealBin/lib";

use MetaCPAN::Server;
MetaCPAN::Server::to_app();
