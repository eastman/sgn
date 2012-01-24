=head1 NAME

SGN::Controller::Qtl- controller for solQTL

=cut

package SGN::Controller::Qtl;

use Moose;
use namespace::autoclean;
use File::Spec::Functions;
use List::MoreUtils qw /uniq/;
use File::Temp qw / tempfile /;
use File::Path qw / mkpath  /;
use File::Copy;
use File::Basename;
use File::Slurp;
use Try::Tiny;
use URI::FromHash 'uri';
use Cache::File;
use Path::Class;
use Bio::Chado::Schema;
use CXGN::Phenome::Qtl;

BEGIN { extends 'Catalyst::Controller'}  

sub view : PathPart('qtl/view') Chained Args(1) {
    my ($self, $c, $id) = @_;
    $c->res->redirect("/qtl/population/$id");
}


sub population : PathPart('qtl/population') Chained Args(1) {
    my ( $self, $c, $id) = @_;
    
    if ( $id !~ /^\d+$/ ) 
    { 
        $c->throw_404("$id is not a valid population id.");
    }  
    elsif ( $id )
    {
        my $schema = $c->dbic_schema('CXGN::Phenome::Schema');
        my $rs = $schema->resultset('Population')->find($id);                             
        if ($rs)  
        { 
            $self->is_qtl_pop($c, $id);
            if ( $c->stash->{is_qtl_pop} ) 
            {
                my $userid = $c->user->get_object->get_sp_person_id if $c->user;          
                $c->stash(template     => '/qtl/population/index.mas',                              
                          pop          => CXGN::Phenome::Population->new($c->dbc->dbh, $id), 
                          referer      => $c->req->path,             
                          userid       => $userid,
                    );
                $self->_link($c);
                $self->_show_data($c);           
                $self->_list_traits($c);
                $self->genetic_map($c);                
                $self->_correlation_output($c);
            } 
            else 
            {
                $c->throw_404("$id is not a QTL population.");
            }
        }
        else 
        {
            $c->throw_404("There is no QTL population for $id");
        }

    }
    elsif (!$id) 
    {
        $c->throw_404("You must provide a valid population id argument");
    }
}

sub download_phenotype : PathPart('qtl/download/phenotype') Chained Args(1) {
    my ($self, $c, $id) = @_;
    
    $c->throw_404("<strong>$id</strong> is not a valid population id") if  $id =~ m/\D/;
    
    $self->is_qtl_pop($c, $id);
    if ($c->stash->{is_qtl_pop})   
    {
        my $pop             = CXGN::Phenome::Population->new($c->dbc->dbh, $id);
        my $phenotype_file  = $pop->phenotype_file($c);
    
        unless (!-e $phenotype_file || -s $phenotype_file <= 1)
        {
            my @pheno_data;
            foreach ( read_file($phenotype_file) ) 
            {
                push @pheno_data, [ split(/,/) ];
            }
            $c->stash->{'csv'}={ data => \@pheno_data};
            $c->forward("SGN::View::Download::CSV");
        }
    }
    else
    {
        $c->throw_404("<strong>$id</strong> is not a QTL population id");   
    }       
}

sub download_genotype : PathPart('qtl/download/genotype') Chained Args(1) {
    my ($self, $c, $id) = @_;
    
    $c->throw_404("<strong>$id</strong> is not a valid population id") if  $id =~ m/\D/;
   
    $self->is_qtl_pop($c, $id);
    if ($c->stash->{is_qtl_pop})
    {
        my $pop             = CXGN::Phenome::Population->new($c->dbc->dbh, $id);        
        my $genotype_file   = $pop->genotype_file($c);
 
        unless (!-e $genotype_file || -s $genotype_file <= 1)
        {
            my @geno_data;
            foreach ( read_file($genotype_file)) 
            {
                push @geno_data, [ split(/,/) ];
            }
            $c->stash->{'csv'}={ data => \@geno_data};
            $c->forward("SGN::View::Download::CSV");
        }
    }
    else
    {
        $c->throw_404("<strong>$id</strong> is not a QTL population id");   
    }       
}

sub download_correlation : PathPart('qtl/download/correlation') Chained Args(1) {
    my ($self, $c, $id) = @_;
    
    $c->throw_404("<strong>$id</strong> is not a valid population id") if $id =~ m/\D/;

    $self->is_qtl_pop($c, $id);
    if ($c->stash->{is_qtl_pop})
    {
        $c->stash(pop => CXGN::Phenome::Population->new($c->dbc->dbh, $id)); 
        $self->_correlation_output($c);     
        my $corr_file = $c->stash->{corre_table_file};   
        my $base_path = $c->config->{basepath};
        $corr_file    = $base_path . $corr_file;
  
        unless (!-e $corr_file || -s $corr_file <= 1) 
        {
            my @corr_data;
            my $count=1;

            foreach ( read_file($corr_file) )
            {
                if ($count==1) { $_ = "Traits " . $_;}
                s/\s/,/g;
                push @corr_data, [ split (/,/) ];
                $count++;
            }   
            $c->stash->{'csv'}={ data => \@corr_data };
            $c->forward("SGN::View::Download::CSV");
        } 
    }  
    else
    {
            $c->throw_404("<strong>$id</strong> is not a QTL population id");   
    }       
}

sub download_acronym : PathPart('qtl/download/acronym') Chained Args(1) {
    my ($self, $c, $id) = @_;

    $c->throw_404("<strong>$id</strong> is not a valid population id") if  $id =~ m/\D/;
    
    $self->is_qtl_pop($c, $id);
    if ($c->stash->{is_qtl_pop})
    {
        my $pop = CXGN::Phenome::Population->new($c->dbc->dbh, $id);    
        $c->stash->{'csv'}={ data => $pop->get_cvterm_acronyms};
        $c->forward("SGN::View::Download::CSV");
    }
    else
    {
        $c->throw_404("<strong>$id</strong> is not a QTL population id");   
    }       
}


sub _analyze_correlation  {
    my ($self, $c)      = @_;    
    my $pop_id          = $c->stash->{pop}->get_population_id();
    my $pheno_file      = $c->stash->{pop}->phenotype_file($c);
    my $base_path       = $c->config->{basepath};
    my $temp_image_dir  = $c->config->{tempfiles_subdir};
    my $r_qtl_dir       = $c->config->{r_qtl_temp_path};
    my $corre_image_dir = catfile($base_path, $temp_image_dir, "temp_images");
    my $corre_temp_dir  = catfile($r_qtl_dir, "tempfiles");
    
    if (-s $pheno_file) 
    {
        foreach my $dir ($corre_temp_dir, $corre_image_dir)
        {
            unless (-d $dir)
            {
                mkpath ($dir, 0, 0755);
            }
        }

        my (undef, $heatmap_file)     = tempfile( "heatmap_${pop_id}-XXXXXX",
                                                  DIR      => $corre_image_dir,
                                                  SUFFIX   => '.png',
                                                  UNLINK   => 0,
                                                  OPEN     => 0,
                                                );

        my (undef, $corre_table_file) = tempfile( "corre_table_${pop_id}-XXXXXX",
                                                  DIR      => $corre_image_dir,
                                                  SUFFIX   => '.txt',
                                                  UNLINK   => 0,
                                                  OPEN     => 0,
                                                );

        my ( $corre_commands_temp, $corre_output_temp ) =
            map
        {
            my ( undef, $filename ) =
                tempfile(
                    File::Spec->catfile(
                        CXGN::Tools::Run->temp_base($corre_temp_dir),
                        "corre_pop_${pop_id}-$_-XXXXXX"
                         ),
                    UNLINK => 0,
                    OPEN   => 0,
                );
            $filename
        } qw / in out /;

        {
            my $corre_commands_file = $c->path_to('/cgi-bin/phenome/correlation.r');
            copy( $corre_commands_file, $corre_commands_temp )
                or die "could not copy '$corre_commands_file' to '$corre_commands_temp'";
        }
        try 
        {
            my $r_process = CXGN::Tools::Run->run_cluster(
                'R', 'CMD', 'BATCH',
                '--slave',
                "--args $heatmap_file $corre_table_file $pheno_file",
                $corre_commands_temp,
                $corre_output_temp,
                {
                    working_dir => $corre_temp_dir,
                    max_cluster_jobs => 1_000_000_000,
                },
                );

            $r_process->wait;
            "sleep 5"
       }
        catch 
        {
            my $err = $_;
            $err =~ s/\n at .+//s; #< remove any additional backtrace
            #     # try to append the R output
            try{ $err .= "\n=== R output ===\n".file($corre_output_temp)->slurp."\n=== end R output ===\n" };
            # die with a backtrace
            Carp::confess $err;
        };

        $heatmap_file      = fileparse($heatmap_file);
        $heatmap_file      = $c->generated_file_uri("temp_images",  $heatmap_file);
        $corre_table_file  = fileparse($corre_table_file);
        $corre_table_file  = $c->generated_file_uri("temp_images",  $corre_table_file);
       
        $c->stash( heatmap_file     => $heatmap_file, 
                   corre_table_file => $corre_table_file
                 );  
    } 
}

sub _correlation_output {
    my ($self, $c)      = @_;
    my $pop             = $c->{stash}->{pop};
    my $base_path       = $c->config->{basepath};
    my $temp_image_dir  = $c->config->{tempfiles_subdir};   
    my $corre_image_dir = catfile($base_path, $temp_image_dir, "temp_images");
    my $cache           = Cache::File->new( cache_root  => $corre_image_dir, 
                                            cache_umask => 002
                                          );
    $cache->purge();

    my $key_h           = "heat_" . $pop->get_population_id();
    my $key_t           = "corr_table_" . $pop->get_population_id();   
    my $heatmap         = $cache->get($key_h);
    my $corre_table     = $cache->get($key_t); 
   
    
    unless ($heatmap) 
    {
        $self->_analyze_correlation($c);
        $heatmap = $c->stash->{heatmap_file};
        $corre_table  = $c->stash->{corre_table_file};
        $cache->set($key_h, $heatmap, "30 days");
        $cache->set($key_t, $corre_table, "30 days");
        
    }
  
    $heatmap     = undef if -z $c->get_conf('basepath')  . $heatmap;   
    $corre_table = undef if -z $c->get_conf('basepath') . $corre_table;
    
    $c->stash( heatmap_file     => $heatmap,
               corre_table_file => $corre_table,
             );  
 
    $self->_get_trait_acronyms($c);
}


sub _list_traits {
    my ($self, $c) = @_;      
    my $population_id = $c->stash->{pop}->get_population_id();
    my @phenotype;  
    
    if ($c->stash->{pop}->get_web_uploaded()) 
    {
        my @traits = $c->stash->{pop}->get_cvterms();
       
        foreach my $trait (@traits)  
        {
            my $trait_id   = $trait->get_user_trait_id();
            my $trait_name = $trait->get_name();
            my $definition = $trait->get_definition();
            
            my ($min, $max, $avg, $std, $count)= $c->stash->{pop}->get_pop_data_summary($trait_id);
            
            $c->stash( trait_id   => $trait_id,
                       trait_name => $trait_name
                );
            
            my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
            my $cvterm = $schema->resultset('Cv::Cvterm')->find(name => $trait_name);
            my $trait_link;
                    
            if ($cvterm)
            {                
                $c->stash(cvterm_id =>$cvterm->id);
                $self->_link($c);
                $trait_link = $c->stash->{cvterm_page};                
            } else
            {
                $self->_link($c);
                $trait_link = $c->stash->{trait_page};
            }
            
            my $qtl_analysis_page = $c->stash->{qtl_analysis_page}; 
            push  @phenotype,  [ map { $_ } ( $trait_link, $min, $max, $avg, $count, $qtl_analysis_page ) ];               
        }
    }
    else 
    {
        my @cvterms = $c->stash->{pop}->get_cvterms();
        foreach my $cvterm( @cvterms )
        {
            my $cvterm_id = $cvterm->get_cvterm_id();
            my $cvterm_name = $cvterm->get_cvterm_name();
            my ($min, $max, $avg, $std, $count)= $c->stash->{pop}->get_pop_data_summary($cvterm_id);
            
            $c->stash( trait_name => $cvterm_name,
                       cvterm_id  => $cvterm_id
                );

            $self->_link($c);
            my $qtl_analysis_page = $c->stash->{qtl_analysis_page};
            my $cvterm_page = $c->stash->{cvterm_page};
            push  @phenotype,  [ map { $_ } ( $cvterm_page, $min, $max, $avg, $count, $qtl_analysis_page ) ];
        }
    }
    $c->stash->{traits_list} = \@phenotype;
}

#given $c and a population id, checks if it is a qtl population and stashes true or false
sub is_qtl_pop {
    my ($self, $c, $id) = @_;
    my $qtltool = CXGN::Phenome::Qtl::Tools->new();
    my @qtl_pops = $qtltool->has_qtl_data();

    foreach my $qtl_pop ( @qtl_pops )
    {
        my $pop_id = $qtl_pop->get_population_id();
        $pop_id == $id ? $c->stash(is_qtl_pop => 1) && last 
                       : $c->stash(is_qtl_pop => 0)
                       ;
    }
}


sub _link {
    my ($self, $c) = @_;
    my $pop_id     = $c->stash->{pop}->get_population_id();
    
    {
        no warnings 'uninitialized';
        my $trait_id   = $c->stash->{trait_id};
        my $cvterm_id  = $c->stash->{cvterm_id};
        my $trait_name = $c->stash->{trait_name};
        my $term_id    = $trait_id ? $trait_id : $cvterm_id;
        my $graph_icon = qq | <img src="/documents/img/pop_graph.png" alt="run solqtl"/> |;
    
        $self->_get_owner_details($c);
        my $owner_name = $c->stash->{owner_name};
        my $owner_id   = $c->stash->{owner_id};   
   
        $c->stash( cvterm_page        => qq |<a href="/chado/cvterm.pl?cvterm_id=$cvterm_id">$trait_name</a> |,
                   trait_page         => qq |<a href="/phenome/trait.pl?trait_id=$trait_id">$trait_name</a> |,
                   owner_page         => qq |<a href="/solpeople/personal-info.pl?sp_person_id=$owner_id">$owner_name</a> |,
                   guideline          => qq |<a href="/qtl/submission/guide">Guideline</a> |,
                   phenotype_download => qq |<a href="/qtl/download/phenotype/$pop_id">Phenotype data</a> |,
                   genotype_download  => qq |<a href="/qtl/download/genotype/$pop_id">Genotype data</a> |,
                   corre_download     => qq |<a href="/qtl/download/correlation/$pop_id">Correlation data</a> |,
                   acronym_download   => qq |<a href="/qtl/download/acronym/$pop_id">Trait-acronym key</a> |,
                   qtl_analysis_page  => qq |<a href="/phenome/qtl_analysis.pl?population_id=$pop_id&amp;cvterm_id=$term_id" onclick="Qtl.waitPage()">$graph_icon</a> |,
            );
    }
    
}

sub _get_trait_acronyms {
    my ($self, $c) = @_;
    if ( $c->stash->{heatmap_file} ) 
    {
        $c->stash(trait_acronym_pairs => $c->stash->{pop}->get_cvterm_acronyms());
    }
    else 
    {
        $c->stash(trait_acronym_pairs => undef );
    }
}

sub _get_owner_details {
    my ($self, $c) = @_;
    my $owner_id   = $c->stash->{pop}->get_sp_person_id();
    my $owner      = CXGN::People::Person->new($c->dbc->dbh, $owner_id);
    my $owner_name = $owner->get_first_name()." ".$owner->get_last_name();    
    
    $c->stash( owner_name => $owner_name,
               owner_id   => $owner_id
        );
    
}

sub _show_data {
    my ($self, $c) = @_;
    my $user_id    = $c->stash->{userid};
    my $user_type  = $c->user->get_object->get_user_type() if $c->user;
    my $is_public  = $c->stash->{pop}->get_privacy_status();
    my $owner_id   = $c->stash->{pop}->get_sp_person_id();
    
    if ($user_id) 
    {        
        ($user_id == $owner_id || $user_type eq 'curator') ? $c->stash(show_data => 1) 
                  :                                          $c->stash(show_data => undef)
                  ;
    } else
    { 
        $is_public ? $c->stash(show_data => 1) 
                   : $c->stash(show_data => undef)
                   ;
    }            
}

sub set_stat_option : PathPart('qtl/stat/option') Chained Args(0) {
    my ($self, $c)  = @_;
    my $pop_id      = $c->req->param('pop_id');
    my $stat_params = $c->req->param('stat_params');
    my $file        = $self->stat_options_file($c, $pop_id);

    if ($file) 
    {
        my $f = file( $file )->openw
            or die "Can't create file: $! \n";

        if ( $stat_params eq 'default' ) 
        {
            $f->print( "default parameters\tYes" );
        } 
        else 
        {
            $f->print( "default parameters\tNo" );
        }  
    }
    $c->res->content_type('application/json');
    $c->res->body({undef});                

}

sub stat_options_file {
    my ($self, $c, $pop_id) = @_;
    my $login_id            = $c->user()->get_object->get_sp_person_id() if $c->user;
    
    if ($login_id) 
    {
        my $qtl = CXGN::Phenome::Qtl->new($login_id);
        my ($temp_qtl_dir, $temp_user_dir) = $qtl->create_user_qtl_dir($c);
        return  catfile( $temp_user_dir, "stat_options_pop_${pop_id}.txt" );
    }
    else 
    {
        return;
    }
}

    
sub qtl_form : PathPart('qtl/form') Chained Args {
    my ($self, $c, $type, $pop_id) = @_;  
    
    my $userid = $c->user()->get_object->get_sp_person_id() if $c->user;
    
    unless ($userid) 
    {
       $c->res->redirect( '/solpeople/login.pl' );
    }
    
    $type = 'intro' if !$type; 
   
    if (!$pop_id and $type !~ /intro|pop_form/ ) 
    {
     $c->throw_404("Population id argument is missing");   
    }

    if ($pop_id and $pop_id !~ /^([0-9]+)$/)  
    {
        $c->throw_404("<strong>$pop_id</strong> is not an accepted argument. 
                        This form expects an all digit population id, instead of 
                        <strong>$pop_id</strong>"
                     );   
    }

    $c->stash( template => $self->get_template($c, $type),
               pop_id   => $pop_id,
               guide    => qq |<a href="/qtl/submission/guide">Guideline</a> |,
               referer  => $c->req->path,
               userid   => $userid
            );   
 
}

sub templates {
    my $self = shift;
    my %template_of = ( intro      => '/qtl/qtl_form/intro.mas',
                        pop_form   => '/qtl/qtl_form/pop_form.mas',
                        pheno_form => '/qtl/qtl_form/pheno_form.mas',
                        geno_form  => '/qtl/qtl_form/geno_form.mas',
                        trait_form => '/qtl/qtl_form/trait_form.mas',
                        stat_form  => '/qtl/qtl_form/stat_form.mas',
                        confirm    => '/qtl/qtl_form/confirm.mas'
                      );
        return \%template_of;
}


sub get_template {
    my ($self, $c, $type) = @_;        
    return $self->templates->{$type};
}

sub submission_guide : PathPart('qtl/submission/guide') Chained Args(0) {
    my ($self, $c) = @_;
    $c->stash(template => '/qtl/submission/guide/index.mas');
}

sub genetic_map {
    my ($self, $c)  = @_;
    my $mapv_id     = $c->stash->{pop}->mapversion_id();
    my $map         = CXGN::Map->new( $c->dbc->dbh, { map_version_id => $mapv_id } );
    my $map_name    = $map->get_long_name();
    my $map_sh_name = $map->get_short_name();
  
    $c->stash( genetic_map => qq | <a href=/cview/map.pl?map_version_id=$mapv_id>$map_name ($map_sh_name)</a> | );

}

sub search_help : PathPart('qtl/search/help') Chained Args(0) {
    my ($self, $c) = @_;
    $c->stash(template => '/qtl/search/help/index.mas');
}

sub show_search_results : PathPart('qtl/search/results') Chained Args(0) {
    my ($self, $c) = @_;
    my $trait = $c->req->param('trait');
    $trait =~ s/(^\s+|\s+$)//g;
    $trait =~ s/\s+/ /g;
               
    my $rs = $self->search_qtl_traits($c, $trait);

    if ($rs)
    {
        my $rows = $self->mark_qtl_traits($c, $rs);
                                                        
        $c->stash(template   => '/qtl/search/results.mas',
                  data       => $rows,
                  query      => $c->req->param('trait'),
                  pager      => $rs->pager,
                  page_links => sub {uri ( query => { trait => $c->req->param('trait'), page => shift } ) }
            );
    }
    else 
    {
        $c->stash(template   => '/qtl/search/results.mas',
                  data       => undef,
                  query      => undef,
                  pager      => undef,
                  page_links => undef,
            );
    }
}

sub search_qtl_traits {
    my ($self, $c, $trait) = @_;
    
    my $rs;
    if ($trait)
    {
        my $schema    = $c->dbic_schema("Bio::Chado::Schema");
        my $cv_id     = $schema->resultset("Cv::Cv")->search(
            {name => 'solanaceae_phenotype'}
            )->single->cv_id;

        $rs = $schema->resultset("Cv::Cvterm")->search(
            { name  => { 'LIKE' => '%'.$trait .'%'},
              cv_id => $cv_id,            
            },          
            {
              columns => [ qw/ cvterm_id name definition / ] 
            },    
            { 
              page     => $c->req->param('page') || 1,
              rows     => 10,
              order_by => 'name'
            }
            );       
    }
    return $rs;      
}

sub mark_qtl_traits {
    my ($self, $c, $rs) = @_;
    my @rows =();
    
    if (!$rs->single) 
    {
        return undef;
    }
    else 
    {  
        my $qtltool  = CXGN::Phenome::Qtl::Tools->new();
        my $yes_mark = qq |<font size=4 color="#0033FF"> &#10003;</font> |;
        my $no_mark  = qq |<font size=4 color="#FF0000"> X </font> |;

        while (my $cv = $rs->next) 
        {
            my $id   = $cv->cvterm_id;
            my $name = $cv->name;
            my $def  = $cv->definition;

            if (  $qtltool->is_from_qtl( $id ) ) 
            {                         
                push @rows, [ qq | <a href="/chado/cvterm.pl?cvterm_id=$id">$name</a> |, $def, $yes_mark ];
           
            }
            else 
            {
                push @rows, [ qq | <a href="/chado/cvterm.pl?cvterm_id=$id">$name</a> |, $def, $no_mark ];
            }      
        } 
        return \@rows;
    } 
}


sub qtl_traits : PathPart('qtl/traits') Chained Args(1) {
    my ($self, $c, $index) = @_;
    
    if ($index =~ /^\w{1}$/) 
    {
        my $traits_list = $self->map_qtl_traits($c, $index);
    
        $c->stash( template    => '/qtl/traits/index.mas',
                   index       => $index,
                   traits_list => $traits_list
            );
    }
    else 
    {
        $c->res->redirect('/search/qtl');
    }
}

sub all_qtl_traits : PathPart('qtl/traits') Chained Args(0) {
    my ($self, $c) = @_;
    $c->res->redirect('/search/qtl');
}

sub filter_qtl_traits {
    my ($self, $index) = @_;

    my $qtl_tools = CXGN::Phenome::Qtl::Tools->new();
    my ( $all_traits, $all_trait_d ) = $qtl_tools->all_traits_with_qtl_data();

    return [
        sort { $a cmp $b  }
        grep { /^$index/i }
        uniq @$all_traits
    ];
}

sub map_qtl_traits {
    my ($self, $c, $index) = @_;

    my $traits_list = $self->filter_qtl_traits($index);
    
    my @traits_urls;
    if (@{$traits_list})
    {
        foreach my $trait (@{$traits_list})
        {
            my $cvterm = CXGN::Chado::Cvterm::get_cvterm_by_name( $c->dbc->dbh, $trait );
            my $cvterm_id = $cvterm->get_cvterm_id();
            if ($cvterm_id)
            {
                push @traits_urls,
                [
                 map { $_ } 
                 (
                  qq |<a href=/chado/cvterm.pl?cvterm_id=$cvterm_id>$trait</a> |
                 )
                ];
            }
            else
            {
                my $t = CXGN::Phenome::UserTrait->new_with_name( $c->dbc->dbh, $trait );
                my $trait_id = $t->get_user_trait_id();
                push @traits_urls,
                [
                 map { $_ } 
                 (
                  qq |<a href=/phenome/trait.pl?trait_id=$trait_id>$trait</a> |
                 )
                ];
            }
        }
    }
   
    return \@traits_urls;
}

__PACKAGE__->meta->make_immutable;
####
1;
####
