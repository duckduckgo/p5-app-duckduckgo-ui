package Curses::UI::SearchBox;
# ABSTRACT: Extension of Curses::UI::TextEntry
use Moo;

extends 'Curses::UI::TextEntry';

after delete_character => sub {
    shift->draw;
};

1;
