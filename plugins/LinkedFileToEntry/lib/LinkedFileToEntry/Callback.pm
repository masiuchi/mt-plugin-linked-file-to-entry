package LinkedFileToEntry::Callback;
use strict;
use warnings;

use MT::Entry;
use MT::Template;

{
    my %resync;

    sub init_app {
        my $orig_text      = \&MT::Entry::text;
        my $orig_text_more = \&MT::Entry::text_more;
        no warnings 'redefine';
        *MT::Entry::text = sub {
            my $entry = shift;
            my $text = $orig_text->( $entry, @_ );
            _needs_db_sync( $entry, 0 );
            unless (@_) {
                if ( $entry->linked_file && $entry->linked_file ne '*' ) {
                    if ( my $res = MT::Template::_sync_from_disk($entry) ) {
                        $text = $orig_text->( $entry, $res );
                        _needs_db_sync( $entry, 1 );
                    }
                }
            }
            return defined $text ? $text : '';
        };
        *MT::Entry::text_more = sub {
            my $entry = shift;
            my $text_more = $orig_text_more->( $entry, @_ );
            _needs_db_sync( $entry, 0 );
            unless (@_) {
                if (   $entry->linked_file_more
                    && $entry->linked_file_more ne '*' )
                {
                    if ( my $res = MT::Template::_sync_from_disk($entry) ) {
                        $text_more = $orig_text_more->( $entry, $res );
                        _needs_db_sync( $entry, 1 );
                    }
                }
            }
            return defined $text_more ? $text_more : '';
        };
    }

    sub take_down {
        return unless %resync;
        for my $entry ( values %resync ) {
            next unless $entry;
            $entry->save;
        }
        %resync = ();
    }

    sub _needs_db_sync {
        my $entry = shift;
        if ( scalar @_ > 0 && $entry->id ) {
            $resync{ $entry->id } = $_[0] ? $entry : undef;
        }
        else {
            my $id = $entry->id or return;
            return defined $resync{$id} ? 1 : 0;
        }
    }
}

sub tmpl_src_edit_entry {
    my ( $cb, $app, $tmpl ) = @_;

    my $insert = quotemeta <<'__MTML__';
  <mt:else eq="tags">
__MTML__

    my $mtml = <<'__MTML__';
  <__trans_section component="LinkedFileToEntry">
  <mtapp:setting
    id="linked_file"
    class="sort-enabled"
    label="<__trans phrase="Link to File (text)">"
    label_class="top-level">
    <input type="text" name="linked_file" <mt:if name="linked_file">value="<mt:var name="linked_file">"</mt:if>/>
  </mtapp:setting>

  <mtapp:setting
    id="linked_file_more"
    class="sort-enabled"
    label="<__trans phrase="Link to File (text_more)">"
    label_class="top-level">
    <input type="text" name="linked_file_more" <mt:if name="linked_file_more">value="<mt:var name="linked_file_more">"</mt:if>/>
  </mtapp:setting>
  </__trans_section>

__MTML__

    $$tmpl =~ s/($insert)/$mtml$1/;
}

sub tmpl_param_edit_entry {
    my ( $cb, $app, $param, $tmpl ) = @_;

    my $id    = $app->param('id')             or return;
    my $entry = MT->model('entry')->load($id) or return;

    $param->{linked_file}      = $entry->linked_file;
    $param->{linked_file_more} = $entry->linked_file_more;
}

sub pre_save_entry {
    my ( $cb, $app, $obj, $orig ) = @_;

    $obj->linked_file( $app->param('linked_file') );
    $obj->linked_file_more( $app->param('linked_file_more') );

    if ( defined $obj->linked_file && $obj->linked_file ne '' ) {
        MT::Template::_sync_to_disk( $obj, $obj->text ) or return;
    }

    if ( defined $obj->linked_file_more && $obj->linked_file_more ne '' ) {
        no warnings 'redefine';
        local *MT::Entry::text        = \&MT::Entry::text_more;
        local *MT::Entry::linked_file = \&MT::Entry::linked_file_more;
        MT::Template::_sync_to_disk( $obj, $obj->text ) or return;
    }

    _needs_db_sync( $obj, 0 );

    return 1;
}

1;
