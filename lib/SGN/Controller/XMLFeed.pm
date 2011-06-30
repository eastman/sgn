

package SGN::Controller::XMLFeed;

use Moose;

BEGIN { extends "Catalyst::Controller"; }

use CXGN::Phenome::Locus;
use XML::Feed;
use XML::Feed::Entry;
use Data::Dumper;

# simple implementation of an xml feed for loci

# creates a new feed every time called. 
# next improvement: use Catalyst::Model::XML::Feed for caching feeds.

sub feed :Path('/feed') :Args(2) { 
    my ($self, $c, $type, $id) = @_;

    if ($type !~ /locus/i) { return; }
    
    my $locus = CXGN::Phenome::Locus->new($c->dbc->dbh(), $id);

    # create the feed object
    my $feed = XML::Feed->new();

    # get the data to fill into the fee object
    my %feed_data = $locus->get_edits("01/01/2005");

    

    # @feed_data is a complex data structure. Parse it somehow

    my @parsed_feed_data = @{$feed_data{loci}}; 
    foreach my $f (@parsed_feed_data) { # step through all the items of the parsed data
	# create a new feed entry for each item in the feed data.
	my $entry = XML::Feed::Entry->new();


	my $body = "";

	$body = <<INFO;

locus symbol: $f->{locus_symbol}\n
gene activity: $f->{gene_activity}\n
linkage group: $f->{linkage_group}\n
lg arm: $f->{locus_name}\n
description: $f->{description}\n
update by: $f->{updated_by}\n

INFO

#                                     'original_symbol' => 'sun',
#                                     'locus_symbol' => 'sun',
#                                     'create_date' => '2008-03-05 14:55:49.612399-05',
#                                     'locus_id' => '1434',
#                                     'updated_by' => '206',
#                                     'description' => undef,
#                                     'obsolete' => 'f',
#                                     'linkage_group' => '7',
#                                     'debug' => 0,
#                                     'dbh' => $VAR_DUMP1->{'images'}[0][0]{'dbh'},
#                                     'locus_name' => 'Sun1642 fruit shape',
#                                     'sp_person_id' => '206',
#                                     'locus_history_id' => '141',
#                                     'gene_activity' => ''
#                                   }, 'CXGN::Phenome::Locus::LocusHistory' ),
    


# 	foreach my $k (%$f) { 
# 	    $body .= " $k = $f->{$k}";
# 	}
	my $content = XML::Feed::Content->new({ body=>$body });
	$entry->content($content);
	$entry->title($f->{locus_id}." has been edited.");
	$entry->link("http://solgenomics.net/phenome/locus_display.pl?locus_id=$id");
       
	$feed->add_entry($entry);
       
 
    }
    $c->res->content_type('application/rss+xml');
    #return the feed as xml.
    $c->res->body($feed->as_xml());

    #$c->res->body("<pre>".Dumper(\%feed_data)."</pre>");

}
    
1;
