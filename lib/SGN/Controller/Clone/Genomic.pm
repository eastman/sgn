package SGN::Controller::Clone::Genomic;
use namespace::autoclean;
use Moose;
use Carp;

use Memoize;
use File::Basename;
use File::Slurp qw/slurp/;

use CXGN::DB::DBICFactory;
use CXGN::Genomic::Clone;
use CXGN::Page;
use CXGN::PotatoGenome::Config;
use CXGN::PotatoGenome::FileRepository;
use CXGN::TomatoGenome::Config;

extends 'SGN::Controller::Clone';

has 'bcs' => (
    is => 'ro',
    isa => 'Bio::Chado::Schema',
    lazy_build => 1,
);
sub _build_bcs {
    CXGN::DB::DBICFactory->open_schema('Bio::Chado::Schema');
}

# /maps/physical/clone_annot_download.pl
sub clone_annot_download {
    my ( $self, $c ) = @_;

    my $page = CXGN::Page->new('Clone Annotation Download','Robert Buels');
    my ($id,$set,$format) = $page->get_encoded_arguments('id','annot_set','annot_format');

    my %content_types = ( gamexml => 'text/xml',
			  gff3 => 'text/plain',
			  tar => 'application/octet-stream',
			);

    my $clone = CXGN::Genomic::Clone->retrieve($id);
    $clone
	or $page->is_bot_request && exit
	    or $page->error_page('Clone not found','No clone was found with that id');

    my %files =  $self->_is_tomato($clone) ? CXGN::TomatoGenome::BACPublish::sequencing_files( $clone, $c->config->{'ftpsite_root'} ) :
	         $self->_is_potato($clone) ? $self->_potato_seq_files( $c, $clone ) :
		     $page->error_page("No file", "No files available for that clone");

    %files
	or $page->is_bot_request && exit
	    or $page->error_page('No Annotations found','No annotation files were found for that clone');

    if (my $file = $files{$set eq 'all' ? $format : $set.'_'.$format}) {
        my $type = $content_types{$format} || 'text/plain';
        my $basename = basename($file);
        print "Content-Type: $type\n";
        print "Content-Disposition: attachment; filename=$basename\n";
        print "\n";
        print slurp($file);
    } elsif ( !$page->is_bot_request) {
        $page->error_page('Not Available',"No annotation set is available in format $format for analysis $set");
    }
}

# find the chado organism for a clone
sub _clone_organism {
    my ( $self, $clone ) = @_;
    $self->bcs->resultset('Organism::Organism')->find( $clone->library_object->organism_id );
}

sub _is_tomato {
    my ( $self, $clone ) = @_;
    return lc $self->_clone_organism($clone)->species eq 'solanum lycopersicum';
}
sub _is_potato {
    my ( $self, $clone ) = @_;
    return lc $self->_clone_organism($clone)->species eq 'solanum tuberosum';
}

sub _clone_seq_project_name {
    my ( $self, $clone ) = @_;
    if( $self->_is_tomato( $clone ) ) {
        my $chr = $clone->chromosome_num;
        return "Chromosome $chr" if defined $chr;
        return 'none';
    } elsif( $self->_is_potato( $clone ) ) {
	return $clone->seqprops->{project_country} || 'unknown';
    } else {
	return 'none';
    }
}

sub _potato_seq_files {
    my ( $self, $c, $clone, $repos_path ) = @_;

    return unless $clone->latest_sequence_name;
    return unless $clone->seqprops->{project_country};

    $repos_path ||=  CXGN::PotatoGenome::Config->load_locked->{repository_path};

    return unless -d $repos_path;

    my $repos = CXGN::PotatoGenome::FileRepository->new( $repos_path );

    my $seq = $repos->get_file( class         => 'SingleCloneSequence',
				sequence_name => $clone->latest_sequence_name,
				project       => $clone->seqprops->{project_country},
				format => 'fasta',
			      );
    #warn $clone->clone_name." -> ".$seq;
    return ( seq => $seq );
}

  #make an ftp site link
sub _ftp_seq_repos_link {
    my ( $self, $c, $clone ) = @_;

    my $ftp_base = $c->config->{ftpsite_url};

    if( $self->_is_tomato( $clone ) ) {
	my $chr = $clone->chromosome_num;
	my $chrnum = $chr;
	$chrnum = 0 if $chr eq 'unmapped';
	my $ftp_subdir =   $chr ? sprintf("chr%02d/",$chrnum) : '';
	my $project_name = $chr ? $chr eq 'unmapped' ? 'Unmapped Clones '
	    : "Chromosome $chrnum "
		: '';
	my $bac_dir = CXGN::TomatoGenome::Config->load_locked->{'bac_publish_subdir'};
	return qq|<a href="$ftp_base/$bac_dir/$ftp_subdir">${project_name}Sequencing repository (FTP)</a>|;
    }
    elsif( $self->_is_potato( $clone ) ) {
	my $country = $clone->seqprops->{project_country} || '';
	my $bac_dir = CXGN::PotatoGenome::Config->load_locked->{'bac_publish_subdir'};
	my $subdir =  $country ? "$country/" : '';
	return qq|<a href="$ftp_base/$bac_dir/$subdir">$country Sequencing repository (FTP)</a>|;
    }

    return '<span class="ghosted">not available</span>';
}


__PACKAGE__->meta->make_immutable;
1;
