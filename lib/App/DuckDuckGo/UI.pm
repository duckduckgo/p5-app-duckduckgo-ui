package App::DuckDuckGo::UI;

use Moo;

our $VERSION = 'devel';

use Curses;
use DDP;
use Curses::UI::POE;
use Curses::UI::TextEditor;
use WWW::DuckDuckGo;
use URI::Encode qw/uri_decode uri_encode/;
use JSON;
use LWP::Simple;
use POE 'Component::Client::HTTP';
use HTTP::Request;

use App::DuckDuckGo::UI::Config;

has config => (
    is => 'ro',
    default => sub { App::DuckDuckGo::UI::Config->new },
);

has ui => (
    is => 'ro',
    default => sub {
        my $self = shift;
        Curses::UI::POE->new(
            -clear_on_exit => 1,
            #-debug => 1,
            -color_support => 1,
            inline_states => {
                _start => sub {
                    $_[HEAP]->{ua} = POE::Component::Client::HTTP->spawn(Alias => 'ua', Timeout => 20, FollowRedirects => 1);
                },
                http_response => sub { 
                    my $method = $_[10]->[1];
                    $self->$method(@_);
                },
            }
        )
    }
);

has window => (
    is => 'ro',
    builder => 1,
    lazy => 1,
);

sub _build_window {
    shift->ui->add(
        'window', 'Window',
        -title => "DuckDuckGo",
        -titlefullwidth => 1,
        -border => 1,
        -bfg => "black",
        -titlereverse => 0,
    )
}

has widgets => (
    is => 'ro',
    builder => 1,
    lazy => 1,
);

has result_wrapper => (
    is => 'ro',
    builder => 1,
    lazy => 1,
);

sub _build_result_wrapper {
    my $self = shift;
    $self->window->add(
        'res_wrap', 'Container',
        -vscrollbar => 'right',
        #-height => $self->window->height - $self->widgets->{searchbox}->height - 3, # make it fit between the entry and the "statusbar"
    ) 
}

sub _build_widgets {
    my $self = shift;
    {
        searchbox => $self->window->add(
            undef, 'TextEntry',
            -border => 1,
            -bfg => 'red',
            -onblur => sub { $self->ui->clear_binding(KEY_ENTER) }
        ),
        zci_box => $self->result_wrapper->add(
            undef, 'Listbox',
            -htmltext => 1,
            -border => 1,
            -titlereverse => 0,
            -userdata => {name => 'zci'}
        ),
        deep_box => $self->result_wrapper->add(
            undef, 'ResultBox',
            -htmltext => 1,
            #-vscrollbar => 'right',
            -userdata => {name => 'deep'}
        ),
        statusbar => $self->window->add(
            undef, 'TextViewer',
            -singleline => 1,
            -text => "",
            -y => $self->window->height - 3,
            -fg => 'blue',
        ),
        autocompleter => $self->window->add(
            undef, 'Listbox',
            -htmltext => 1,
            -y => $self->result_wrapper->{-y},
            -height => 0,
        ),
        window => $self->window,
        result_wrapper => $self->result_wrapper,
    }
}

has ddg => (
    is => 'ro',
    default => sub {
        WWW::DuckDuckGo->new(
            params => { t => 'cli', %{shift->config->{params}} },
            http_agent_name => "App::DuckDuckGo::UI/$VERSION",
        )
    }
);

sub scale {
    # properly scale the two result listboxes
    my $self = shift;
    my $top = $self->widgets->{searchbox}{-y} + $self->widgets->{searchbox}->height;
    $self->result_wrapper->{-height} = $self->window->height - $self->widgets->{searchbox}->height - 3;
    $self->result_wrapper->{-y} = $top;
    $self->widgets->{zci_box}{-height} = ($#{$self->widgets->{zci_box}->values})+$top;
    $self->widgets->{zci_box}->layout;
    $self->widgets->{deep_box}{-y} = $top + $self->widgets->{zci_box}->canvasheight;
    #$deep_box->{-height} = $res_wrap->canvasheight - $zci_box->height;
    $_->layout and $_->draw for ($self->widgets->{zci_box}, $self->widgets->{deep_box}, $self->window);
}

sub set_results {
    my ($self, $box) = (shift, shift);
    # takes the name of a listbox, and an array of hashrefs ({ URL => description })
    my @values;
    my %labels;
    for my $result (@_) {
        push @values, $_ for keys %{$result};
        for (keys %{$result}) {
            my $desc = $$result{$_};
            $desc =~ s/'''//g;
            $labels{$_} = $desc;
        }
    }
    if (!@values) {
        print STDERR "No values, hiding box $box\n";
        $self->widgets->{$box}->hide;
    } else {
        $self->widgets->{$box}->show;
        $self->widgets->{$box}->values(\@values);
        $self->widgets->{$box}->labels(\%labels);
    }
    $self->scale;
}

sub autocomplete_and_add {
    my ($self, $searchbox, $char) = @_;

    $searchbox->add_string($char);

    my $results = $self->autocomplete($searchbox->text);

    return $searchbox;
}

#
# Semi-logical part
# 

# Deep results API
sub fill_deep {
    my ($self, $request, $response) = @_[OBJECT, ARG0+1, ARG1+1];
    my @out;

    return unless $response->[0]->content; # no results?

    my $results;
    eval { $results = from_json($response->[0]->content); };
    return if $@; # this likes to whine about incomplete or malformed json, just return if it does

    for my $result (@$results) {
        push @out, { $result->{c} => "<bold>".$result->{t}."</bold>\n".($result->{a} ? $result->{a} : $result->{c}) } if defined $result->{c} and defined $result->{t};
    }
    $self->set_results(deep_box => @out);
}

sub deep {
    my ($self, $call) = @_;
    my $request = HTTP::Request->new(GET => "https://api.duckduckgo.com/$call");
    POE::Kernel->post('ua', 'request', 'http_response', $request, 'fill_deep');
}

# Autocompletion!
sub fill_ac {
    my ($self, $request, $response) = @_[OBJECT, ARG0+1, ARG1+1];
    $self->widgets->{zci_box}->values(from_json($response->[0]->content)->[1]);
    $self->widgets->{zci_box}->title(undef);

    $self->scale;
}

sub autocomplete {
    my ($self, $text) = @_;
    my $request = HTTP::Request->new(GET => 'https://duckduckgo.com/ac/?type=list&q=' . uri_encode($text));
    POE::Kernel->post('ua', 'request', 'http_response', $request, 'fill_ac');
}

sub duck {
    my $self = shift;
    $self->widgets->{searchbox}->text($_[0]);
    my $zci;
    eval { $zci = $self->ddg->zci(shift); };
    if ($@) {
        $self->ui->error("$@");
        return;
    }

    if ($zci->has_redirect) {
        $self->browse($zci->redirect);
        return;
    }

    my @results;
    
    if (defined $zci->_json->{Calls} && $zci->_json->{Calls}{deep}) {
        $self->deep($zci->_json->{Calls}{deep});
    }
    
    $self->widgets->{zci_box}->title(""); # clear the title, in case there is no heading
    $self->widgets->{zci_box}->title($zci->heading) if $zci->has_heading;

    if ($zci->has_results) {
        for my $zci_box (@{$zci->results}) {
            push @results, { $zci_box->first_url => "<bold>".$zci_box->text."</bold>" } if $zci_box->has_first_url && $zci_box->has_text;
        }
    }

    if ($zci->has_answer) {
        push @results, { 0 => "<bold>Answer: </bold>".$zci->answer };
    }

    if ($zci->has_abstract_text && $zci->has_abstract_url) {
        push @results, { $zci->abstract_url->as_string => "<bold>Abstract: </bold>".$zci->abstract_text };
    }

    if ($zci->has_definition && $zci->has_definition_url) {
        push @results, { $zci->definition_url->as_string => $zci->definition };
    }

    if ($zci->has_related_topics_sections) {
        for my $sec (keys %{$zci->related_topics_sections}) {
            my $section = $zci->related_topics_sections;
            $section = $$section{$sec};
            for my $zci_box (@{$section}) {
                push @results, { $zci_box->first_url => $zci_box->text } if $zci_box->has_first_url && $zci_box->has_text;
            }
        }
    }

    if (scalar @results) {
        #$self->widgets->{zci_box}->show;
        $self->set_results(zci_box => @results);
    } else {
        # FIXME: Hide the ZCI box when it isn't needed
        #$self->widgets->{zci_box}->hide;
        #$self->scale;
    }
}


#
# Launch a browser!
#
sub browse {
    my ($self, $URI) = @_;
    $self->ui->leave_curses;
    system split(
        /\s+/,
        sprintf($self->config->{browser}, "$URI")
    );
    $self->ui->error("Error $? ($!) in browser") if $?;
    $self->ui->reset_curses;
}


#
# Builtin keybindings
#

# TODO: Mouse support - directly clicking on results to visit them?
#$zci_box->onSelectionChange(sub {
#    browse shift->get_active_value;
#});

sub default_bindings {
    my $self = shift;
    my ($cui, $zci_box, $deep_box, $searchbox, $statusbar) = ($self->ui, $self->widgets->{zci_box}, $self->widgets->{deep_box}, $self->widgets->{searchbox}, $self->widgets->{statusbar});
    $cui->set_binding(sub {exit}, "\cq");
    $cui->set_binding(sub {exit}, "\cc");

    $cui->set_binding(sub {
        my $cui = shift;
        $cui->layout;
        $cui->draw;
    }, "\cl");

    $searchbox->set_binding(sub { $self->duck($searchbox->get) if $searchbox->get; }, KEY_ENTER);
    $searchbox->set_binding(sub { $zci_box->focus }, KEY_DOWN);

    $_->set_binding(sub { $searchbox->focus }, '/') for ($zci_box, $deep_box);

# Bind space to show a dialog containing the full result
    $deep_box->set_binding(sub {
        my $this = shift;
        my $message = $this->labels->{$this->get_active_value};
        $message =~ s{^<bold>(.+?)</bold>(?: - )?}{};
        $cui->dialog(
            -title => $1,
            -message => $message . " (".$this->get_active_value.")",
        );
    }, ' ');

    $zci_box->set_binding(sub {
        my $URL = shift->get_active_value;# or ($cui->dialog(shift->get_active_) and return); #TODO: handle value==0 somehow
        if ($URL !~ m{^[a-z]+://}) { # FIXME: make this handle category pages and post-disambig results
            #my $q = $1 // $URL; $q =~ s/_/ /g;
            $self->duck(uri_decode($1 // $URL));
        } else {
            $self->browse($URL);
        }
    }, $_) for (KEY_ENTER, KEY_RIGHT, "l");

    $deep_box->set_binding(sub {
        $self->browse(shift->get_active_value);
    }, $_) for (KEY_ENTER, KEY_RIGHT, "l");

    $deep_box->set_mouse_binding(sub {
        my ($this, $event, $x, $y) = @_;
        my $newypos = $this->{-yscrpos} + $y;
        my $i = (($newypos - ($newypos%2 ? 1 : 0)) + ($this->{-yscrpos} ? $this->{-yscrpos}+0.5 : 0 ) ) /2; print STDERR "clicked: $i\n";
        #$self->browse($this->values->[$i]) if (@{$this->{-values}} and $newypos >= 0); # FIXME
        $self->ui->error("Clicker support is buggy and rather broken.\nURL I think you clicked: ".$this->values->[$i]);
    }, BUTTON1_CLICKED);

# Show the URL
    $_->onSelectionChange(sub {
        $statusbar->text(shift->get_active_value);
        $deep_box->layout; $deep_box->draw;
        $statusbar->layout; $statusbar->draw;
    }) for ($zci_box, $deep_box);

    $_->onFocus(sub {
        $statusbar->text(shift->get_active_value or "");
        $statusbar->draw;
    }) for ($zci_box, $deep_box);

#
# Override the up and down handlers on the listboxes to handle moving between them
#
    $_->set_binding(sub {
        my $this = shift;
        if ($this->{-ypos} >= $this->{-max_selected} and $this->userdata->{name} eq 'zci') {
            $deep_box->focus;
        } else {
            $this->{-routines}{'option-next'}->($this);
            #print STDERR "ypos: ".($this->{-ypos}*($this->userdata->{name} eq 'deep' ?2:1) % $this->canvasheight).", canvasheight: ".$this->canvasheight.", yscrpos: ";
            #$this->{-yscrpos}+=($this->userdata->{name} eq 'deep' ?2:1) unless ($this->{-ypos}*($this->userdata->{name} eq 'deep' ?2:1) % $this->canvasheight);
            #p $this->{-yscrpos};
            #$this->draw;
        }
    }, KEY_DOWN) for ($zci_box, $deep_box);

    $_->set_binding(sub {
        my $this = shift;
        if ($this->{-ypos} == 0) {
            my $target = $this->userdata->{name} eq 'zci' ? $searchbox : $zci_box;
            $target->focus;
        } else {
            $this->{-routines}{'option-prev'}->($this);
        }
    }, KEY_UP) for ($zci_box, $deep_box);


    # Autocompleter
    $searchbox->set_binding(sub { $self->autocomplete_and_add(@_) }, '');
}

sub configure_widgets {
    my $self = shift;
    return unless defined $self->config->{interface};
    for my $widget (keys %{$self->config->{interface}}) {
        print STDERR "\"$widget\" is not a valid widget name.\n" and return if not defined $self->widgets->{$widget};
        for my $key (keys %{$self->config->{interface}{$widget}}) {
            print STDERR "Setting $key on $widget ...\n";

            $self->widgets->{$widget}{$key} = $self->config->{interface}{$widget}{$key} and next
                if $key =~ /^-\w+$/;

            if ($key eq 'keys') {
                for (keys %{$self->config->{interface}{$widget}{keys}}) {
                    my $key_name = $_;
                    if (/^<(\w+)>$/) {
                        $key_name = "KEY_" . uc $1;
                        $key_name = Curses->$key_name;
                    }
                    $self->widgets->{$widget}->set_binding($self->config->{interface}{$widget}{keys}{$_}, $key_name);
                }
            }
            else {
                print STDERR "Unknown option!";
            }
        }
    }
}

sub run {
    my $self = shift;
    $self->window->layout; $self->window->draw;

    $self->default_bindings;
    $self->configure_widgets;

    $self->set_results(
        zci_box =>
            {'https://duckduckgo.com/'         => '<bold>Homepage</bold>'},
            {'https://duckduckgo.com/about'    => '<bold>About</bold>'},
            {'https://duckduckgo.com/goodies/' => '<bold>Goodies</bold>'},
            {'https://duckduckgo.com/feedback' => '<bold>Feedback</bold>'},
            {'https://duckduckgo.com/privacy'  => '<bold>Privacy</bold>'},
    );

    POE::Kernel->run;
}


1;
