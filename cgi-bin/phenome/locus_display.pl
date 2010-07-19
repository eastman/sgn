use strict;
use warnings;
use CXGN::Page;


use CXGN::People::PageComment;
use CXGN::People;
use CXGN::Contact;
use CXGN::Page::FormattingHelpers qw(
        info_section_html
        page_title_html
        columnar_table_html
        info_table_html
        html_optional_show
        html_alternate_show
        tooltipped_text
      );
use CXGN::Page::Widgets qw / collapser /;
use CXGN::Phenome::Locus;
use CXGN::Phenome::Locus::LinkageGroup;


use CXGN::Chado::CV;
use CXGN::Chado::Feature;
use CXGN::Chado::Publication;
use CXGN::Chado::Pubauthor;


use CXGN::Sunshine::Browser;
use CXGN::Tools::Identifiers qw/parse_identifier/;
use CXGN::Tools::List qw/distinct/;

use CXGN::Phenome::Locus::LocusPage;
use SGN::Image;
use HTML::Entities;

our $c;
my $d = CXGN::Debug->new();


#####################
use CGI qw / param /;
use CXGN::DB::Connection;
use CXGN::Login;

my $q = CGI->new();
my $dbh = CXGN::DB::Connection->new();
my $login = CXGN::Login->new($dbh);

my $person_id = $login->has_session();

my $user = CXGN::People::Person->new($dbh, $person_id);
my $user_type = $user->get_user_type();

my $locus_id = $q->param("locus_id") ;
my $action =  $q->param("action");

$c->forward_to_mason_view('/locus/index.mas',  action=> $action,  locus_id => $locus_id , person_id=>$person_id, user_type=>$user_type, dbh=>$dbh);




#############
my $time = time();


my $script = "/phenome/locus_display.pl?locus_id=$locus_id";

my $locus= CXGN::Phenome::Locus->new( $dbh, $locus_id  );

my $locus_name = $locus->get_locus_name();
my $organism   = $locus->get_common_name();

my @owners   = $locus->get_owners();


#$page->header("SGN $organism locus: $locus_name");

print $c->render_mason("/locus/initialize.mas",
            locus_id => $locus_id
);

####################################################
#get all dbxref  annotations: pubmed, ncbi sequences, GO, PO, tgrc link
####################################################
my @allele_objs = $locus->get_alleles();    #array of allele objects
my ( $tgrc, $pubs, $pub_count, $genbank, $gb_count, $onto_ref ) =
    get_dbxref_info($locus, @allele_objs);

##############################
    #display locus details section
#############################

my $locus_html= qq| <table width="100%"><tr><td>|;


#########################
#####################################


if ($locus_name) {
    my $locus_html;
    $locus_html .= "<br />" . $tgrc;
    
}

##########
## Notes and Figures
##########
   
    my $figure_html     = "";
    my $m_figure_html   = "";
    my $figure_subtitle = "";
    my $figures_count;
    my @more_is;
    

    if (
        $locus_name
        && (   $user_type eq 'submitter'
            || $user_type eq 'curator'
            || $user_type eq 'sequencer' )
      )
    {
        $figure_subtitle .= associated_figures($locus, $person_id);
    }
    else {
        $figure_subtitle .=
          qq|<span class= "ghosted">[Add notes, figures or images]</span> |;
    }

    my @figures = $locus->get_figure_ids();

    if (@figures) {    # don't display anything for empty list of figures
        $figure_html .= qq|<table cellpadding="5">|;
        foreach my $figure_id (@figures) {
            $figures_count++;
	    my $figure= SGN::Image->new($locus->get_dbh(), $figure_id);
	    my $figure_name        = $figure->get_name();
            my $figure_description = $figure->get_description();
            my $figure_img  = $figure->get_image_url("medium");
            my $small_image = $figure->get_image_url("thumbnail");
            my $image_page  = "/image/index.pl?image_id=$figure_id";
	    
            my $thickbox =
qq|<a href="$figure_img"  title="<a href=$image_page>Go to image page ($figure_name)</a>" class="thickbox" rel="gallery-figures"><img src="$small_image" alt="$figure_description" /></a> |;
            my $fhtml =
                qq|<tr><td width=120>|
              . $thickbox
              . $figure_name
              . "</td><td>"
              . $figure_description
              . "</td></tr>";
            if ( $figures_count < 3 ) { $figure_html .= $fhtml; }
            else {
                push @more_is, $fhtml;
            }    #more than 3 figures- show these in a hidden div
        }
        $figure_html .= "</table>";  #close the table tag or the first 3 figures
    }
    $m_figure_html .=
      "<table cellpadding=5>";  #open table tag for the hidden figures #4 and on
    my $more = scalar(@more_is);
    foreach (@more_is) { $m_figure_html .= $_; }

    $m_figure_html .= "</table>";    #close tabletag for the hidden figures
    my $more_images;
    if (@more_is) {    #html_optional_show if there are more than 3 figures
        $more_images = html_optional_show(
            "Images",
            "<b>See $more more figures...</b>",
            qq| $m_figure_html |,
            0,                        #< do not show by default
            'abstract_optional_show', #< don't use the default button-like style
        );
    }
    print info_section_html(
        title       => "Notes and figures (" . scalar(@figures) . ")",
        subtitle    => $figure_subtitle,
        contents    => $figure_html . $more_images,
        collapsible => 1,
        collapsed   => 1,
    );

#################################
    #display individuals section
#################################
    my $individuals_html = "";
    my $ind_subtitle     = "";
    if (
        $locus_name
        && (   $user_type eq 'curator'
            || $user_type eq 'submitter'
            || $user_type eq 'sequencer' )
      )
    {
        $ind_subtitle .=
qq| <a href="javascript:Tools.toggleContent('associateIndividualForm', 'locus_accessions')">[Associate accession]</a> |;
        $individuals_html = associate_individual($locus, $person_id);
    }
    else {
        $ind_subtitle .=
          qq|<span class= "ghosted">[Associate accession]</span> |;
    }
    my ( $html, $ind_count ) = get_individuals_html($locus, $user_type);
    $individuals_html .= $html;

    print info_section_html(
        title       => "Accessions and images  ($ind_count)",
        subtitle    => $ind_subtitle,
        contents    => $individuals_html,
        id          => "locus_accessions",
        collapsible => 1,
        collapsed   => 1,
    );

#################################
    #display alleles section
#################################

    my $allele_count = scalar(@allele_objs);

    #map the allele objects to an array ref of the alleles data
    my @allele_data;
    my $allele_data;
    my $allele_subtitle;
    if (
        $locus_name
        && (   $user_type eq 'submitter'
            || $user_type eq 'curator'
            || $user_type eq 'sequencer' )
      )
    {
        $allele_subtitle .=
qq { <a href="allele.pl?locus_id=$locus_id&amp;action=new">[Add new allele]</a>};
    }
    else {
        $allele_subtitle .=
          qq | <span class="ghosted">[Add new Allele]</span> |;
    }

    foreach my $a (@allele_objs) {

        my $allele_id = $a->{allele_id};

        my $allele_synonyms;
        my @allele_aliases = $a->get_allele_aliases();
        foreach my $a_synonym (@allele_aliases) {
            $allele_synonyms .= $a_synonym->get_allele_alias() . "  ";
        }
        if ( !$allele_synonyms ) { $allele_synonyms = "[add new]"; }
        my $allele_synonym_link =
qq |<a href= "allele_synonym.pl?allele_id=$allele_id&amp;action=new">$allele_synonyms</a> |;
        my $allele_edit_link = get_allele_edit_links($a, $user);
        my $phenotype        = $a->get_allele_phenotype();
        my @individuals      = $a->get_individuals();
        my $individual_link  = "";
        my $ind_count        = scalar(@individuals);

        $individual_link .=
qq|<a href="allele.pl?action=view&amp;allele_id=$allele_id">$ind_count </a>|;

        push @allele_data,
          [
            map { $_ } (
                "<i>" . $a->get_allele_symbol . "</i>",
                $a->get_allele_name,
                $allele_synonym_link,
qq|<div align="left"><a href="allele.pl?action=view&amp;allele_id=$allele_id"> |
                  . $phenotype
                  . "</a></div>",
                $individual_link,
                $allele_edit_link,
            )
          ];

    }
    if (@allele_data) {

        $allele_data .= columnar_table_html(
            headings => [
                'Allele symbol', 'Allele name',
                'Synonyms',      'Phenotype',
                'Accessions',
            ],
            data         => \@allele_data,
            __alt_freq   => 2,
            __alt_width  => 1,
            __alt_offset => 3,
        );
    }

    print info_section_html(
        title       => "Known alleles ($allele_count)",
        subtitle    => $allele_subtitle,
        contents    => $allele_data,
        collapsible => 1,
        collapsed   => 1,
    );

    ###########################               ASSOCIATED LOCI
    #my @locus_groups= $locus->get_locusgroups();
    #my $direction;
    my $al_count = $locus->count_associated_loci();

    my $associated_locus_sub;
    my $associate_locus_form;
    if (
        (
               $user_type eq 'curator'
            || $user_type eq 'submitter'
            || $user_type eq 'sequencer'
        )
      )
    {

        if ($locus_name) {
            $associated_locus_sub .=
		qq |<a href="javascript:Tools.toggleContent('associateLocusForm', 'locus2locus');Tools.getOrganisms()">[Associate new locus]</a> |;
            $associate_locus_form =
		CXGN::Phenome::Locus::LocusPage::associate_locus_form($locus_id);
        }
    }
else {
    $associated_locus_sub .=
	qq |<span class ="ghosted"> [Associate new locus] </span> |;
}

#printing associated loci section dynamically
my $dyn = $c->render_mason("/locus/network.mas");

print info_section_html(
    title       => "Associated loci ($al_count) ",
    subtitle    => $associated_locus_sub,
    contents    => $associate_locus_form . $dyn,
    id          => 'locus2locus',
    collapsible => 1,
    collapsed   => 1,
    );

$d->d( "!!!Printing locus2locus :  " . ( time() - $time ) . "\n");

##################  SUNSHINE BROWSER

my $locus2locus_graph =
    CXGN::Sunshine::Browser::include_on_page( 'locus', $locus_id );

my $networkbrowser_link =
    qq { View <b>$locus_name</b> relationships in the stand-alone <a href="/tools/networkbrowser/?type=locus&name=$locus_id">network browser</a>. Please note that this tool is a prototype.<br /><br /><br /> };

if ( $al_count > 0 ) {
    print info_section_html(
	title       => "Associated loci - graphical view [beta version]",
	contents    => $networkbrowser_link . $locus2locus_graph,
	id          => 'locus2locus_graph',
	collapsible => 1,
	collapsed   => 1,
        );
}
else {
    print info_section_html(
	title       => "Associated loci - graphical view",
	collapsible => 0,
	collapsed   => 1,
	id          => 'locus2locus_graph'
        );
    
}


#####################           UNIGENES AND SOLCYC

my @unigenes = $locus->get_unigenes();
my $unigene_count=0;
my $solcyc_count=0;
foreach (@unigenes) { 
    $unigene_count++ if $_->get_status eq 'C'; 
}

print $c->render_mason("/locus/solcyc.mas");

$d->d( "!!!Got SolCyc links :  " . ( time() - $time ) . "\n");

my $associate_unigene_form;
if (
    (
     $user_type eq 'curator'
     || $user_type eq 'submitter'
     || $user_type eq 'sequencer'
    )
    )
{
    if ($locus_name) { 
	$associate_unigene_form= qq|<a href="javascript:Tools.toggleContent('associateUnigeneForm', 'unigenes' )">[Associate new unigene]</a> |;
	$associate_unigene_form .= 
	    CXGN::Phenome::Locus::LocusPage::associate_unigene_form($locus_id);
    }
}
my $sequence_links;
if ($locus_name) {
    if ( !$genbank ) {
	$genbank = qq|<span class=\"ghosted\">none </span>|;
    }
    $genbank .=
	qq|<a href="/chado/add_feature.pl?type=locus&amp;type_id=$locus_id&amp;refering_page=$script&amp;action=new">[Associate new genbank sequence]</a><br />|;
    	
    
    #printing associated unigenes section dynamically
    my $dyn_unigenes = CXGN::Phenome::Locus::LocusPage::include_locus_unigenes();
    $d->d( "!!!Got unigenes :  " . ( time() - $time ) . "\n");

    $sequence_links = info_table_html(
	'SGN Unigenes'       => $dyn_unigenes . $associate_unigene_form,
	'GenBank Accessions' => $genbank,
        'Genome Matches'     => genomic_annots_html($locus),
        __border             => 0,
       );
}
my $seq_count = $gb_count + $unigene_count;
print info_section_html(
    title       => "Sequence annotations ($seq_count)",
    contents    => $sequence_links,
    id          => 'unigenes',
    collapsible => 1,
    collapsed   => 1,
    );
$d->d("!!!got sequence :  " . ( time() - $time ) . "\n");

##########literature ########################################
my ( $pub_links, $pub_subtitle );
if ($pubs) {
    $pub_links = info_table_html(
	"  "     => $pubs,
	__border => 0,
        );
}

if (
    $locus_name
    && (   $user_type eq 'curator'
	   || $user_type eq 'submitter'
	   || $user_type eq 'sequencer' )
    )
{
    $pub_subtitle .=
	qq|<a href="/chado/add_publication.pl?type=locus&amp;type_id=$locus_id&amp;refering_page=$script&amp;action=new"> [Associate publication] </a>|;
}
else {
    $pub_subtitle =
	qq|<span class=\"ghosted\">[Associate publication]</span>|;
}

my $disabled = "true";
if ($person_id) { $disabled = "false"; }
$pub_subtitle .=
    qq | <a href="javascript:void(0)"onclick="window.open('locus_pub_rank.pl?locus_id=$locus_id','publication_list','width=600,height=400,status=1,location=1,scrollbars=1')">[Matching publications]</a> |;

$d->d("!!!Printing pub links :  " . ( time() - $time ) . "\n");

print info_section_html(
    title       => "Literature annotation ($pub_count)",
    subtitle    => $pub_subtitle,
    contents    => $pub_links,
    collapsible => 1,
    collapsed   => 1,
    );

######################################## Ontology details ##############

my $ont_count = $locus->count_ontology_annotations(); #= scalar(@$onto_ref);

my $ontology_add_link = "";
my $ontology_subtitle;
if (
    (
     $user_type eq 'curator'
     || $user_type eq 'submitter'
     || $user_type eq 'sequencer'
    )
    )
{
    if ($locus_name) {
        $ontology_subtitle .= qq|<a href="javascript:Tools.toggleContent('associateOntologyForm', 'locus_ontology')">[Add ontology annotations]</a> |;
        $ontology_add_link = $c->render_mason("/locus/associate_ontology.mas",
            locus_id => $locus_id
        );
    }
}
else {
    $ontology_subtitle =
	qq |<span class = "ghosted"> [Add ontology annotations]</span> |;
}

my $dyn_ontology_info = $c->render_mason("/locus/ontology.mas");

print info_section_html(
    title       => "Ontology annotations ($ont_count)",
    subtitle    => $ontology_subtitle,
    contents    => $ontology_add_link . $dyn_ontology_info,
    id          => "locus_ontology",
    collapsible => 1,
    collapsed   => 1,
    );


####add page comments
my $comments;

if ($locus_name) {

    $comments = $c->render_mason('/page/comments.mas', object_type=>'locus', object_id=>$locus_id, referer=>$script);
    
}
print $comments;



#########################################################
#functions used in the locus page:
##

sub get_allele_edit_links {
    my $allele   = shift;
    my $user= shift;
    my $login_user_id    = $user->get_sp_person_id();
    my $locus    = $allele->get_locus();
    my $locus_id = $locus->get_locus_id();

    my $allele_edit_link = "";
   
    my $allele_id        = $allele->get_allele_id();
    if (   ( $allele->get_sp_person_id() == $login_user_id )
        || ( $user->get_user_type() eq 'curator' ) )
    {
        $allele_edit_link =
qq | <a href="allele.pl?action=edit&amp;allele_id=$allele_id">[Edit]</a> |;
    }
    else { $allele_edit_link = qq | <span class="ghosted">[Edit]</span> |; }
}


#######################

sub get_dbxref_info {
    my $locus      = shift;
    my $locus_name = $locus->get_locus_name();
    my %dbs        = $locus->get_dbxref_lists()
	;    #hash of arrays. keys=dbname values= dbxref objects
    my (@alleles) = @_;    #$locus->get_alleles();
    #add the allele dbxrefs to the locus dbxrefs hash...
    #This way the alleles associated publications and sequences are also printed on the locus page
    #it might be a good idea to pring a link to the allele next to each allele-derived annotation
    
    foreach my $a (@alleles) {
        my %a_dbs = $a->get_dbxref_lists();
	
        foreach my $a_db_name ( keys %a_dbs )
        {    #add allele_dbxrefs to the locus_dbxrefs list
            my %seen = ()
		; #hash for assisting filtering of duplicated dbxrefs (from allele annotation)
            foreach ( @{ $dbs{$a_db_name} } ) {
                $seen{ $_->[0]->get_accession() }++;
            }    #populate with the locus_dbxrefs
            foreach ( @{ $a_dbs{$a_db_name} } ) {    #and filter duplicates
                push @{ $dbs{$a_db_name} }, $_
		    unless $seen{ $_->[0]->get_accession() }++;
            }
        }
    }
    my ( $tgrc, $pubs, $genbank );
    ##tgrc
    foreach ( @{ $dbs{'tgrc'} } ) {
        if ( $_->[1] eq '0' ) {
            my $url       = $_->[0]->get_urlprefix() . $_->[0]->get_url();
            my $accession = $_->[0]->get_accession();
            $tgrc .=
		qq|$locus_name is a <a href="$url$accession" target="blank">TGRC gene</a><br />|;
        }
    }
    
    my $abs_count = 0;
    my @sorted;
 
    @sorted = sort { $a->[0]->get_accession() <=> $b->[0]->get_accession() } @{ $dbs{PMID} } if  defined @{ $dbs{PMID} } ;
 
    foreach ( @sorted  ) {
        if ( $_->[1] eq '0' ) {    #if the pub is not obsolete
            $pubs .= get_pub_info( $_->[0], 'PMID', $abs_count++ );
        }
    }
    foreach ( @{ $dbs{'SGN_ref'} } ) {
        $pubs .= get_pub_info( $_->[0], 'SGN_ref', $abs_count++ )
	    if $_->[1] eq '0';
    }
    
    my $gb_count = 0;
    foreach ( @{ $dbs{'DB:GenBank_GI'} } ) {
        if ( $_->[1] eq '0' ) {
            $gb_count++;
            my $url = $_->[0]->get_urlprefix() . $_->[0]->get_url();
            my $gb_accession =
		$locus->CXGN::Chado::Feature::get_feature_name_by_gi(
		    $_->[0]->get_accession() );
            my $description = $_->[0]->get_description();
            $genbank .=
		qq|<a href="$url$gb_accession" target="blank">$gb_accession</a> $description<br />|;
        }
    }
    my @ont_annot;
    
    # foreach ( @{$dbs{'GO'}}) { push @ont_annot, $_; }
    # foreach ( @{$dbs{'PO'}}) { push @ont_annot, $_; }
    # foreach ( @{$dbs{'SP'}}) { push @ont_annot, $_; }
    
    return ( $tgrc, $pubs, $abs_count, $genbank, $gb_count, \@ont_annot );
}

########################

sub abstract_view {
    my $pub           = shift;
    my $abs_count     = shift;
    my $abstract      = encode_entities($pub->get_abstract() );
    my $authors       = encode_entities($pub->get_authors_as_string() );
    my $journal       = $pub->get_series_name();
    my $pyear         = $pub->get_pyear();
    my $volume        = $pub->get_volume();
    my $issue         = $pub->get_issue();
    my $pages         = $pub->get_pages();
    my $abstract_view = html_optional_show(
        "abstracts$abs_count",
        'Show/hide abstract',
	qq|$abstract <b> <i>$authors.</i> $journal. $pyear. $volume($issue). $pages.</b>|,
        0,                           #< do not show by default
        'abstract_optional_show',    #< don't use the default button-like style
	);
    return $abstract_view;
}    #

sub get_pub_info {
    my ( $dbxref, $db, $count ) = @_;
    my $pub_info;
    my $accession = $dbxref->get_accession();
    my $pub_title = $dbxref->get_publication()->get_title();
    my $year= $dbxref->get_publication()->get_pyear();
    my $pub_id    = $dbxref->get_publication()->get_pub_id();
    my $abstract_view =
	abstract_view( $dbxref->get_publication(), $count );
    $pub_info =
	qq|<div><a href="/chado/publication.pl?pub_id=$pub_id" >$db:$accession</a> $pub_title ($year) $abstract_view </div><br /> |;
    return $pub_info;
}    #


sub get_individuals_html {
    my $locus        = shift;
    my $user_type=shift;
    my @individuals = $locus->get_individuals();

    my $html;
    my %imageHoA
      ; # hash of image arrays. Keys are individual_ids, values are arrays of image_ids
    my %individualHash;
    my %imageHash;
    my @no_image;
    my $more_html;
    my $more;    #count the number of accessions in the optional_show box
    my $count
      ; # a scalar for checking if there are accessions with images in the optional box

    if (@individuals) {
        $html      .= "<table>";
        $more_html .= "<table>";

        my %imageHoA
          ; # hash of image arrays. Keys are individual ids values are arrays of image ids
        foreach my $i (@individuals) {
            my $individual_id   = $i->get_individual_id();
            my $individual_name = $i->get_name();
            $individualHash{$individual_id} = $individual_name;

            my @images =
              $i->get_images();    #array of all associated image objects
            foreach my $image (@images) {
                my $image_id = $image->get_image_id();

                #my $img_src_tag= $image->get_img_src_tag("thumbnail");
                $imageHash{$image_id} = $image;
                push @{ $imageHoA{$individual_id} }, $image_id;
            }

            #if there are no associated images with this individual:
            if ( !@images ) { push @no_image, $individual_id; }
        }
        my $ind_count = 0;

        # Print the whole thing sorted by number of members and name.
        for
          my $individual_id ( sort { @{ $imageHoA{$b} } <=> @{ $imageHoA{$a} } }
            keys %imageHoA )
        {
            $ind_count++;
            my $individual_name = $individualHash{$individual_id};
            my $individual_obsolete_link =
              get_individual_obsolete_link($locus,$individual_id, $user_type);
            my $link =
qq|<a href="individual.pl?individual_id=$individual_id">$individual_name </a>  |;
            if ( $ind_count < 4 )
            { #print the first 3 individuals by default. The rest will be hidden
                $html .=
qq|<tr valign="top"><td>$link</td> <td> $individual_obsolete_link </td>|;
            }
            else {
                $count++;
                $more++;
                $more_html .=
                  qq|<tr><td>$link </td><td> $individual_obsolete_link</td> |;
            }

        #print only 5 images, if there are more write the number of total images
            my $image_count = ( $#{ $imageHoA{$individual_id} } );    #+1;
            if ( $image_count > 4 ) { $image_count = 4; }
            for my $i ( 0 .. $image_count ) {
                my $image_id = $imageHoA{$individual_id}[$i];
                #my $image    = $imageHash{$image_id};
                my $image = SGN::Image->new($locus->get_dbh(), $image_id);
                my $small_image  = $image->get_image_url("thumbnail");
                my $medium_image = $image->get_image_url("medium");
                my $image_page   = "/image/index.pl?image_id=$image_id";
                my $thickbox =
		    qq|<a href="$medium_image" title="<a href=$image_page>Go to image page </a>" class="thickbox" rel="gallery-images"><img src="$small_image" alt="" /></a> |;
                if ( $ind_count < 4 ) { $html .= qq|<td>$thickbox</td>|; }
                else                  { $more_html .= qq|<td>$thickbox</td>|; }
                $image_count--;
            }
            if ( $#{ $imageHoA{$individual_id} } > 4 ) {
                my $image_count = ( $#{ $imageHoA{$individual_id} } ) + 1;
                $html .= qq|<td>... (Total $image_count images)</td>|;
            }
            if   ( $ind_count < 4 ) { $html      .= "</tr>"; }
            else                    { $more_html .= "</tr>"; }
        }
        $html      .= "</table><br />";
        $more_html .= "</table><br />";
        if ( !$count ) {
            my $individual_name;
            my $no_image_count = 0;
            foreach my $individual_id (@no_image) {
                $no_image_count++;
                my $individual_obsolete_link =
		    get_individual_obsolete_link($locus, $individual_id, $user_type);
                if ( $no_image_count < 26 ) {
                    $individual_name = $individualHash{$individual_id};
                    $html .=
			qq|<a href="individual.pl?individual_id=$individual_id">$individual_name</a>&nbsp$individual_obsolete_link |;
                }
                else {
                    $more++;
                    $more_html .=
			qq|<a href="individual.pl?individual_id=$individual_id">$individual_name</a>&nbsp$individual_obsolete_link |;
                }
            }
        }
        else {
            foreach my $individual_id (@no_image) {
                $more++;
                my $individual_obsolete_link =
		    get_individual_obsolete_link($locus, $individual_id, $user_type);
                my $individual_name = $individualHash{$individual_id};
                $more_html .=
		    qq|<a href="individual.pl?individual_id=$individual_id">$individual_name</a>&nbsp$individual_obsolete_link |;
            }
        }
    }
    
    if ($more) {
        my ( $more_link, $contents ) = collapser(
            {
                linktext => "<b> See $more more accessions </b>",
		
                #hide_state_linktext => $title,
                content   => $more_html,
                collapsed => 1,
                id        => "more_individuals_display"
            }
	    );
        $html .= "$more_link\n$contents";
    }
    return ( $html, scalar(@individuals) );
}    #get_individuals_html

############################javascript code



sub associate_individual {
    
    my $locus         = shift;
    my $locus_id     = $locus->get_locus_id();
    my $sp_person_id = shift;

    my $associate_html = qq^

<div id="associateIndividualForm" style="display: none">
    Accession name:
    <input type="text"
           style="width: 50%"
           id="locus_name"
           onkeyup="Locus.getIndividuals(this.value, '$locus_id');">
    <input type="button"
           id="associate_individual_button"
           value="associate accession"
	   disabled="true"
           onclick="Locus.associateAllele('$sp_person_id');this.disabled=true;">
    <select id="individual_select"
            style="width: 100%"
	    onchange="Locus.getAlleles('$locus_id')"
            size=10>
       </select>

    <b>Would you Like to specify an allele?</b>
    <select id="allele_select"
            style="width: 100%">
    </select>

</div>
^;

    return $associate_html;
}


sub associated_figures {

    my $locus         = shift;
    my $locus_id     = $locus->get_locus_id();
    my $sp_person_id = shift;

    my $associate_html = qq^
       <span>
       <a href="/image/add_image.pl?type_id=$locus_id&type=locus&action=new&refering_page=/phenome/locus_display.pl?locus_id=$locus_id"> 
       [Add notes, figures or images]</a></span>
^;

    return $associate_html;
}


sub get_individual_obsolete_link {
    my $locus                    = shift;
    my $individual_id            = shift;
    my $user_type = shift;
    my $individual_obsolete_link = "";
    my $individual_allele_id = $locus->get_individual_allele_id($individual_id);
    if (   ( $user_type eq 'submitter' )
	   || ( $user_type eq 'curator' )
	   || ( $user_type eq 'sequencer' ) )
    {
        $individual_obsolete_link = qq| 
	    <a href="javascript:Locus.obsoleteIndividualAllele('$individual_allele_id')">[Remove]</a>
	    
	    <div id='obsoleteIndividualAlleleForm' style="display: none">
            <div id='individual_allele_id_hidden'>
	    <input type="hidden" 
	    value=$individual_allele_id
	    id="$individual_allele_id">
	    </div>
	    </div>
	    |;
	
    }
    return $individual_obsolete_link;
}


#######################################################
#returns string html listing of locus sequence matches found in ITAG gbrowse DBs
sub genomic_annots_html {

    my $locus    = shift;
    my $locus_id = $locus->get_locus_id();


    # look up any gbrowse cross-refs for this locus id, if any
    my @xrefs = map {
        $_->xrefs({ -types      => ['match'],
                    -attributes => { sgn_locus_id => $locus_id },
                 }),
    } $c->enabled_feature('gbrowse2');

    return '<span class="ghosted">None</span>'
        unless @xrefs;


    # and now convert each of the matched regions into HTML strings
    # that display them
    return join "\n", map _render_genomic_xref( $_ ), @xrefs;
}

sub _render_genomic_xref {
    my ( $xref ) = @_;

    # look up all the matching locus sequence names
    my @locus_seqnames =
        distinct
        map {
            my $f = $_;
            my $p = parse_identifier(
                $f->target->seq_id,
                'sgn_locus_sequence'
               ) or die "cannot parse " . $f->target->seq_id;
            $p->{ext_id}
        }
        @{$xref->seqfeatures};

    my $linked_img = CGI->a( { href => $xref->url },
                              CGI->img({ #style => "border: 1px solid #ddd; border-top: 0; padding: 1em 0; margin:0",
                                         style => 'border: none',
                                         src   => $xref->preview_image_url })
                            );


    my $sequences_matched =
        @locus_seqnames > 1 ? 'Sequences matched'
                            : 'Sequence matched';

    return join('',
                 '<div style="border: 1px solid #777; padding-bottom: 10px">',
                 info_table_html(
                     'Annotation Set'     => $xref->data_source->description,
                     'Feature(s) matched' => join( ', ', map $_->display_name || $_->primary_id, @{$xref->seqfeatures} ),
                     'Reference Sequence' => $xref->seqfeatures->[0]->seq_id,
                     $sequences_matched   => join( ', ', @locus_seqnames ),
                     #__tableattrs         => qq|summary="" style="margin: 1em auto -1px auto"|,
                     __border             => 0,
                     __multicol           => 3,
                    ),
                 '<hr style="width: 95%" />',
                 $linked_img,
                 '</div>',
                );
}

