package App::DuckDuckGo::UI::Config;
# ABSTRACT: App::DuckDuckGo::UI configuration manager

use Config::Any;

my %defaults = (
    browser => "w3m %s",
    params => {},
    ssl => 0,
    debug => 0,
    filters => {
        #'^https?://(?:www\.)?duckduckgo.([a-z]{2,4})/([A-Z][^?]+|\?[^?]+).*$' => '"https://duckduckgo.$1/lite/".(substr($2,0,1) eq "?" ? "" : "?q=")."$2"',
    },
);

sub new {
    my %config = %defaults;

    my $config_home = $ENV{XDG_CONFIG_HOME} // "$ENV{HOME}/.config";
    my @files = Config::Any->load_stems({
            stems   => ["$config_home/duckduckgo-ui", "./duckduckgo-ui", "/etc/duckduckgo-ui"],
            use_ext => 1,
    });

    for my $file (@files) {
        my $cfg = $$file[0]->{(keys($$file[0]))[0]};
        $config{$_} = $$cfg{$_} for keys %$cfg;
    }

    # Some magic for the filters - reverses the hash and compiles the regexen
    $config{filters} = {reverse %{$config{filters}}};
    $config{filters}->{$_} = qr/$config{filters}->{$_}/ for keys %{$config{filters}};

    return \%config;
}

1;
