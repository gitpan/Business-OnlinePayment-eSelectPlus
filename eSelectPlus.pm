package Business::OnlinePayment::eSelectPlus;

use strict;
use Carp;
use Tie::IxHash;
use Business::OnlinePayment 3;
use Business::OnlinePayment::HTTPS 0.03;
use vars qw($VERSION $DEBUG @ISA);

@ISA = qw(Business::OnlinePayment::HTTPS);
$VERSION = '0.01';
$DEBUG = 0;

sub set_defaults {
    my $self = shift;

    $self->server('esqa.moneris.com');
    $self->port('443');
    $self->path('/gateway2/servlet/MpgRequest');

    $self->build_subs(qw( order_number ));
    # avs_code order_type md5 cvv2_response cavv_response
}

sub submit {
    my($self) = @_;

    #$self->map_fields();
    $self->remap_fields(
        #                => 'order_type',
        #                => 'transaction_type',
        #login            => 'store_id',
        #password         => 'api_token',
        #authorization   => 
        #customer_ip     =>
        #name            =>
        #first_name      =>
        #last_name       =>
        #company         =>
        #address         => 
        #city            => 
        #state           => 
        #zip             => 
        #country         =>
        phone            => 
        #fax             =>
        email            =>
        card_number      => 'pan',
        #expiration        =>
        #                => 'expdate',

        'amount'         => 'amount',
        #invoice_number  =>
        #customer_id     =>
        order_number     => 'order_id',
        authorization    => 'txn_number'

        #cvv2              =>
    );

    my $action = $self->{_content}{'action'};
    if ( $self->{_content}{'action'} =~ /^\s*normal\s*authorization\s*$/i ) {
      $action = 'purchase';
    } elsif ( $self->{_content}{'action'} =~ /^\s*authorization\s*only\s*$/i ) {
      $action = 'preauth';
    } elsif ( $self->{_content}{'action'} =~ /^\s*post\s*authorization\s*$/i ) {
      $action = 'completion';
    } elsif ( $self->{_content}{'action'} =~ /^\s*void\s*$/i ) {
      $action = 'void';
    } elsif ( $self->{_content}{'action'} =~ /^\s*credit\s*$/i ) {
      if ( $self->{_content}{'authorization'} ) {
        $action = 'refund';
      } else {
        $action = 'ind_refund';
      }
    }

    if ( $action =~ /^(purchase|preauth|ind_refund)$/ ) {

      $self->required_fields(
        qw( login password amount card_number expiration )
      );

      #cardexpiremonth & cardexpireyear
      $self->{_content}{'expiration'} =~ /^(\d+)\D+\d*(\d{2})$/
        or croak "unparsable expiration ". $self->{_content}{expiration};
      my( $month, $year ) = ( $1, $2 );
      $month = '0'. $month if $month =~ /^\d$/;
      $self->{_content}{expdate} = $year.$month;

      $self->generate_order_id;

      $self->{_content}{amount} = sprintf('%.2f', $self->{_content}{amount} );

    } elsif ( $action eq 'completion' || $action eq 'void' ) {

      $self->required_fields( qw( login password order_number authorization ) );

    } elsif ( $action eq 'refund' ) {

      $self->required_fields(
        qw( login passowrd order_number authorization )
      );

    }

    $self->{_content}{'crypt_type'} ||= 7;

    #no, values aren't escaped for XML.  their "mpgClasses.pl" example doesn't
    #appear to do so, i dunno
    tie my %fields, 'Tie::IxHash', $self->get_fields( $self->fields );
    my $post_data =
      '<?xml version="1.0"?>'.
      '<request>'.
      '<store_id>'.  $self->{_content}{'login'}. '</store_id>'.
      '<api_token>'. $self->{_content}{'password'}. '</api_token>'.
      "<$action>".
      join('', map "<$_>$fields{$_}</$_>", keys %fields ).
      "</$action>".
      '</request>';

    warn $post_data if $DEBUG > 1;

    my( $page, $response, @reply_headers) = $self->https_post( $post_data );

    #my %reply_headers = @reply_headers;
    #warn join('', map { "  $_ => $reply_headers{$_}\n" } keys %reply_headers )
    #  if $DEBUG;

    #XXX check $response and die if not 200?

    #	avs_code
    #	is_success
    #	result_code
    #	authorization
    #md5 cvv2_response cavv_response ...?

    $self->server_response($page);

    my $result = $self->GetXMLProp($page, 'ResponseCode');

    die "gateway error: ". $self->GetXMLProp( $page, 'Message' )
      if $result =~ /^null$/i;

    if ( $result =~ /^\d+$/ && $result < 50 ) {
      $self->is_success(1);
      $self->result_code( $self->GetXMLProp( $page, 'ISO' ) );
      $self->authorization( $self->GetXMLProp( $page, 'Txn_number' ) );
      $self->order_number( $self->GetXMLProp( $page, 'order_id') );
    } elsif ( $result =~ /^\d+$/ ) {
      $self->is_success(0);
      $self->error_message( $self->GetXMLProp( $page, 'Message' ) );
    } else {
      die "unparsable response received from gateway (response $result)".
          ( $DEBUG ? ": $page" : '' );
    }

}

use vars qw(@oidset);
@oidset = ( 'A'..'Z', '0'..'9' );
sub generate_order_id {
    my $self = shift;
    #generate an order_id if order_number not passed
    unless (    exists ($self->{_content}{order_id})
             && defined($self->{_content}{order_id})
             && length ($self->{_content}{order_id})
           ) {
      $self->{_content}{'order_id'} =
        join('', map { $oidset[int(rand(scalar(@oidset)))] } (1..23) );
    }
}

sub fields {
	my $self = shift;

        #order is important to this processor
	qw(
	  order_id
	  cust_id
	  amount
	  comp_amount
	  txn_number
	  pan
	  expdate
	  crypt_type
	  cavv
	);
}

sub GetXMLProp {
	my( $self, $raw, $prop ) = @_;
	local $^W=0;

	my $data;
	($data) = $raw =~ m"<$prop>(.*?)</$prop>"gsi;
	#$data =~ s/<.*?>/ /gs;
	chomp $data;
	return $data;
}

1;

__END__

=head1 NAME

Business::OnlinePayment::eSelectPlus - Moneris eSelect Plus backend module for Business::OnlinePayment

=head1 SYNOPSIS

  use Business::OnlinePayment;

  ####
  # One step transaction, the simple case.
  ####

  my $tx = new Business::OnlinePayment("eSelectPlus");
  $tx->content(
      type           => 'VISA',
      login          => 'eSelect Store ID,
      password       => 'eSelect API Token',
      action         => 'Normal Authorization',
      description    => 'Business::OnlinePayment test',
      amount         => '49.95',
      name           => 'Tofu Beast',
      address        => '123 Anystreet',
      city           => 'Anywhere',
      state          => 'UT',
      zip            => '84058',
      phone          => '420-867-5309',
      email          => 'tofu.beast@example.com',
      card_number    => '4005550000000019',
      expiration     => '08/06',
      cvv2           => '1234', #optional
  );
  $tx->submit();

  if($tx->is_success()) {
      print "Card processed successfully: ".$tx->authorization."\n";
  } else {
      print "Card was rejected: ".$tx->error_message."\n";
  }

=head1 SUPPORTED TRANSACTION TYPES

=head2 CC, Visa, MasterCard, American Express, Discover

Content required: type, login, password, action, amount, card_number, expiration.

=head1 PREREQUISITES

  URI::Escape
  Tie::IxHash

  Net::SSLeay _or_ ( Crypt::SSLeay and LWP )

=head1 DESCRIPTION

For detailed information see L<Business::OnlinePayment>.

=head1 NOTE

=head1 AUTHOR

Ivan Kohler <ivan-eselectplus@420.am>

=head1 SEE ALSO

perl(1). L<Business::OnlinePayment>.

=cut

