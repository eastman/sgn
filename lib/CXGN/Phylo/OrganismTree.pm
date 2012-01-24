package CXGN::Phylo::OrganismTree;

=head1 NAME

CXGN::Phylo::OrgnanismTree - an object to handle SGN organism  trees

=head1 USAGE

 my $tree = CXGN::Phylo::OrganismTree->new();
 my $root = $tree->get_root();
 my $node = $root->add_child();
 $node->set_name("I'm a child node");
 $node->set_link("http://solgenomics.net/");
 my $child_node = $node->add_child();
 $child_node->set_name("I'm a grand-child node");
 print $tree->generate_newick();

=head1 DESCRIPTION

This is a subcass of L<CXGN::Phylo::Tree>

=head1 AUTHORS

 Naama Menda (nm249@cornell.edu)

=cut

use strict;
use warnings;
use namespace::autoclean;

use HTML::Entities;

use CXGN::DB::DBICFactory;
use CXGN::Chado::Organism;
use CXGN::Tools::WebImageCache;
use CXGN::Phylo::Node;

use base qw / CXGN::Phylo::Tree /;

=head2 function new()

  Synopsis:	my $t = CXGN::Phylo::OrganismTree->new($schema)
  Arguments:	$schema object
  Returns:	an instance of a Tree object.
  Side effects:	creates the object and initializes some parameters.
  Description:	

=cut

sub new {
    my $class = shift;
    my $schema = shift || die "NO SCHEMA OBJECT PROVIDED!!\n";

    my $self = $class->SUPER::new();

    $self->set_schema($schema);

    return $self;
}

#######

=head2 recursive_children

 Usage: $self->recursive_children($nodes_hashref, $organism, $node, $species_info, $is_root)
 Desc:  recursively add child nodes starting from root.
 Ret:   nothing
 Args:  $nodes_hashref (organism_id => CXGN::Chado::Organism),
        $organism object for your root,
        $node object for your root,
        hashref of text species info (for rendering species popups),
        1 (required)
 Side Effects: sets name, label, link, tooltip for nodes, highlites leaf nodes.
 Example:

=cut

sub recursive_children {
    my ( $self, $nodes, $o, $n, $species_cache, $is_root ) = @_;

    # $o is a CXGN::Chado::Organism object
    # $n is a CXGN::Phylo::Node object

    $n->set_name( $o->get_species() );
    my $orgkey = $o->get_organism_id();
    $n->get_label
      ->set_link( "/chado/organism.pl?organism_id="
                  . $o->get_organism_id
                 );
    $n->get_label
      ->set_name( $o->get_species );
    $n->set_tooltip( $n->get_name );
    $n->set_species( $n->get_name );
    $n->set_hide_label( 0 );
    $n->get_label->set_hidden( 0 );

    my $content = do {
        if( my $species_data = $species_cache->thaw($orgkey) ) {
            join '<br />', map {
                    "<b>$_:</b> ".( $species_data->{$_} || '<span class="ghosted">not set</span>' )
                  } sort keys %$species_data
        } else {
            '<span class="ghosted">no data available</span>'
        }
    };

    $content =~ s/\n/ /g;
    $content = encode_entities( $content );

    my $species = $o->get_species;
    for ( $n, $n->get_label ) {
        $_->set_onmouseover(
            "javascript:showPopUp('popup','$content','<b>$species</b>')"
           );
        $_->set_onmouseout(
            "javascript:hidePopUp('popup')"
           );
    }

    my @cl = $n->get_children;

    my @children = $o->get_direct_children;
    foreach my $child (@children) {

        if ( exists( $nodes->{ $child->get_organism_id } )
            && defined( $nodes->{ $child->get_organism_id } ) )
        {

            my $new_node = $n->add_child;
            $self->recursive_children( $nodes, $child, $new_node,
                $species_cache );
        }
    }

    $n->set_hilited(1) if $n->is_leaf;
}

=head2 find_recursive_parent

 Usage: $self->find_recursive_parent($organism, $nodes_hashref)
 Desc:  populate $nodes_hashref  (organism_id=> CXGN::Chado::organism) with recursive parent organisms 
 Ret:   $nodes_hashref
 Args:  $organism object, $nodes_hashref
 Side Effects: none
 Example:

=cut

sub find_recursive_parent {
    my ($self, $organism, $nodes) = @_;

    my $parent = $organism->get_parent;
    if ($parent) {
        my $id = $parent->get_organism_id();

        if ( !$nodes->{$id} ) {
            $nodes->{$id} = $parent;
            $self->find_recursive_parent( $parent, $nodes );
        }
    }
    else { return; }
    return $nodes;
}


=head2 hilite_species

 Usage:        $tree->hilite_species([255,0,0], ['Solanum lycopersicum']);
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub hilite_species {
    my $self = shift;
    my $color_ref = shift;
    my $species_ref = shift;
    
    foreach my $s (@$species_ref) { 
	my $n = $self->get_node_by_name($s);
	$n->set_hilited(1);
	$n->get_label()->set_hilite_color(@$color_ref);
	$n->get_label()->set_hilite(1);
    }
}



=head2 build_tree

 Usage:  $self->build_tree($root_species_name, $org_ids, $speciesinfo_cache)
 Desc:   builds an organism tree starting from $root with a list of species
 Ret:    a newick representation of the tree
 Args:   $root_species_id (species name of root species)
         $org_ids (arrayref of organism IDs)
 Side Effects:  sets tree nodes names and lables, and renders the tree  (see L<CXGN::Phylo::Renderer> )
                calls $tree->generate_newick($root_node, 1)
 Example:

=cut

sub build_tree {
    my ( $self, $root, $organisms, $species_cache ) = @_;
    my $schema    = $self->get_schema();
    my $root_o    = CXGN::Chado::Organism->new_with_species( $schema, $root )
        or die "species '$root' not found";
    my $root_o_id = $root_o->get_organism_id();
    my $organism_link = "/chado/organism.pl?organism_id=";
    my $nodes         = ();
    my $root_node = $self->get_root();    #CXGN::Phylo::Node->new();

    # look up all the organism objects
    my @organisms =
        grep $_, #< filter out missing organisms
        map CXGN::Chado::Organism->new_with_species( $schema, $_ ),
        @$organisms;

    foreach my $o ( @organisms ) {
        my $organism_id = $o->get_organism_id();
        $nodes->{$organism_id} = $o;
        $nodes = $self->find_recursive_parent( $o, $nodes );
    }

    $self->recursive_children( $nodes, $nodes->{$root_o_id}, $root_node,
        $species_cache, 1 );

    $self->set_show_labels(1);

    $root_node->set_name( $root_o->get_species() );
    $root_node->set_link( $organism_link . $root_o_id );
    $self->set_root($root_node);

    $self->d( "FOUND organism "
          . $nodes->{$root_o_id}
          . " root node: "
          . $root_node->get_name()
          . "\n\n" );

    my $newick = $self->generate_newick( $root_node, 1 );

    $self->standard_layout();

    my $renderer     = CXGN::Phylo::PNG_tree_renderer->new($self);
    my $leaf_count   = $self->get_leaf_count();
    my $image_height = $leaf_count * 20 > 120 ? $leaf_count * 20 : 120;

    $self->get_layout->set_image_height($image_height);
    $self->get_layout->set_image_width(800);
    $self->get_layout->set_top_margin(20);
    $self->set_renderer($renderer);

    #$tree->get_layout->layout();
    $self->get_renderer->render();

    return $newick;
}

1;
