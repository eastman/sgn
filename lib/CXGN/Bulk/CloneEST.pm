# Clone EST download script for SGN database
# Lukas Mueller, August 12, 2003

# This bulk download option handles the query 
# Of Clones of type EST.
# Many of its methods are in the Bulk object.

# Modified July 15, 2005
# Modified more August 11, 2005
# Summer Intern Caroline N. Nyenke

# Modified July 7, 2006
# Summer Intern Emily Hart

# Modified July 3rd, 2007
# Alexander Naydich and Matthew Crumb

=head1 NAME

  /CXGN/Bulk/CloneEST.pm
  (A subclass of Bulk)

=head1 DESCRIPTION

  This perl script is used on the bulk download page. The script collects
  identifiers submitted by the user and returns information based on the
  Clone EST Ids entered. It then determines the information the user is
  searching for (Clone name, SGN_C, SGN_T, SGN_E, SGN_U, Build Number,
  Chipname, SGN_S, TUS, Maunal Annotation, Autiomatic Annotation, 
  and Estemated Sequence) and preforms the appropriate querying of the 
  database. The results of the database query are formated and presented
  to the user on a separate page. Options of viewing or downloading
  in text or fasta are available.

=cut

use strict;
use warnings;
use CXGN::Bulk;

package CXGN::Bulk::CloneEST;
use base "CXGN::Bulk";

=head2 process_parameters

  Desc: sub process_parameters
  Args: none
  Ret : 1 if the parameters were OK, 0 if not

  Modifies some of the parameters received set in get_parameters. Preparing
  data for the database query.

=cut

sub process_parameters
{
    my $self = shift;

    # @output_list defines the identity on order of all fields that can be output
    my @output_list = ( 'clone_name', 'SGN_C', 'SGN_T', 'SGN_E', 'SGN_U',
                               'build_nr', 'chipname','SGN_S', 'TUS',
                               'manual_annotation', 'automatic_annotation',
                               'evalue');

    my %links = (clone_name =>
             "/search/est.pl?request_type=10&search=Search&request_id=",
		   SGN_U  => "/search/unigene.pl?unigene_id=",
		   );

    $self->{links} = \%links;
    my @output_fields = ();

    $self->debug("Type of identifier: ".($self->{idType})."");

    # @output_fields is the sub-set of fields that will actually be output.
    foreach my $o (@output_list)
    {
        if (my $value = $self->{$o})
        {
            if ($value eq "on")
            {
                push @output_fields, $o;
            }
        }
    }

    if ($self->{sequence} eq "on")
    {
	push @output_fields, $self->{seq_type};
    }

    $self->{output_list} = \@output_list;
    $self->{output_fields} = \@output_fields;

    my @ids = $self->check_ids();
    if (@ids == ()) {return 0;}
    $self->debug("IDs to be processed:");
    foreach my $i (@ids)
    {
	$i =~ s/^(\w+?)(\d+)(\w+\d+)/$1\-$2\-$3/;
      	$self->debug($i);
    }
    my $has_valid_id = 0;
    foreach my $i(@ids){
	if ($i ne ""){
	    $has_valid_id = 1;
	}
    }
    if(!$has_valid_id){
	return 0;
    }
    $self->{ids} = \@ids;

    return 1; #params were OK if we got here
}

=head2 process_ids

  Desc: sub process_ids
  Args: default;
  Ret : data from database printed to a file;

  Queries database using Persistent (see perldoc Persistent) and
  object oriented perl to obtain data on Bulk Objects using formatted
  IDs.

=cut

sub process_ids
{
    my $self = shift;
    my $db = $self->{db};
    my @output_fields = @{$self->{output_fields}};
    my @return_data = ();
    my @notfound = ();
    my ($dump_fh, $notfound_fh) = $self->create_dumpfile();
    # start querying the database
    my $current_time= time() - $self->{query_start_time};
    $self->debug("Time point 6: $current_time");
    
    my $in_ids = 'IN ('.join(',',(map {$db->quote($_)} @{$self->{ids}})).')'; #makes fragment of SQL query
    my $query = get_query($in_ids, $self->{build_id});

    #warn "using query \n",$query;

    my $sth = $db->prepare($query);

    $self->{query_start_time} = time();
    $sth->execute();
    $current_time = time() - $self->{query_start_time};

    # execute the query and get the data.
    while (my $row = $sth->fetchrow_hashref())
    {
      # crop est_seq if qc_report data is available

      if ( defined($row->{start}) && defined($row->{length}) ) 
      {
	my $start = $row->{start};
	my $length = $row->{length};
	$row->{"est_seq"}=substr($row->{est_seq}, $start, $length);
      }

      $row->{sgn_u}="SGN-U$row->{sgn_u}" if defined($row->{sgn_u});
      $row->{sgn_c}="SGN-C$row->{sgn_c}" if defined($row->{sgn_c});
      $row->{sgn_t}="SGN-T$row->{sgn_t} ($row->{direction})" if defined($row->{sgn_t});
     
      @return_data = map ($row->{lc($_)}, @{$self -> {output_fields}});
      # the pesky manual annotation field contains carriage returns!!!
      foreach my $r (@return_data) {
	$r =~ s/\n//g if $r;
      }
      print $dump_fh (join "\t", @return_data)."\n";
    }
    close($notfound_fh);
    close($dump_fh);

    $self->{query_time} = time() - $self -> {query_start_time};
}

=head2 get_query

  Desc: 
  Args: default;
  Ret : data from database printed to a file;

  Queries database using SQL to obtain data on Bulk Objects using formatted
  IDs.

=cut

sub get_query
{
    my ($in_ids, $build_id) = @_;
    #person might have picked a specific build they're interested in
    my $build_condition = ($build_id eq 'all') ? '' : <<EOSQL;
AND (unigene_build.unigene_build_id = $build_id
     OR unigene_build.unigene_build_id IS NULL)
EOSQL

    return <<EOSQL
SELECT  clone.clone_name,
	clone.clone_id as SGN_C,
	seqread.read_id as SGN_T,
	seqread.direction as direction,
	est.est_id as SGN_E,
	unigene_build.build_nr as build_nr,
	unigene.unigene_id as SGN_U,
	microarray.chip_name as chipname,
	microarray.spot_id as SGN_S,
	microarray.content_specific_tag as TUS,
	est.seq as est_seq,
	qc_report.hqi_start as start,
	qc_report.hqi_length as length,
        (SELECT array_to_string(array(SELECT '"' || m.annotation_text || '"'
                                             || ' -- ' || a.first_name || ' ' || a.last_name
                                      FROM manual_annotations as m
                                      JOIN sgn_people.sp_person as a
                                         ON(m.author_id=a.sp_person_id)
                                      WHERE m.annotation_target_id = clone.clone_id
					AND (m.annotation_target_type_id=1
                                             OR m.annotation_target_type_id IS NULL)
	                              LIMIT 5
                                     ),
                                ' AND ')
        ) AS manual_annotation,
        (SELECT array_to_string(array(SELECT 'MATCHED '
                                             || dl.defline
                                             || ' (evalue:'
                                             || bh.evalue
                                             || ')'
                                      FROM blast_annotations as ba
                                      JOIN blast_hits as bh USING(blast_annotation_id)
                                      JOIN blast_defline as dl USING(defline_id)
                                      WHERE ba.apply_id=unigene.unigene_id
					AND ba.blast_target_id=1
                                        AND ba.apply_type=15
	                              LIMIT 5
                                     ),
                                ' AND ')
        ) AS automatic_annotation,
	est.status
FROM clone
LEFT JOIN seqread ON (clone.clone_id=seqread.clone_id)
LEFT JOIN est ON (seqread.read_id=est.read_id)
LEFT JOIN unigene_member ON (unigene_member.est_id=est.est_id)
LEFT JOIN unigene ON (unigene_member.unigene_id=unigene.unigene_id)
LEFT JOIN unigene_build ON (unigene.unigene_build_id=unigene_build.unigene_build_id)
LEFT JOIN unigene_consensi ON (unigene.consensi_id=unigene_consensi.consensi_id)
LEFT JOIN qc_report ON (est.est_id=qc_report.est_id)
LEFT JOIN microarray ON (clone.clone_id=microarray.clone_id)
WHERE clone.clone_name $in_ids
  AND (est.status=0 OR est.status IS NULL)
  AND (est.flags=0 OR est.flags IS NULL)
$build_condition
ORDER BY clone.clone_id
EOSQL
}

1;
