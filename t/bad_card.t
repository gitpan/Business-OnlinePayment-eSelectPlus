BEGIN {$| = 1; print "1..1\n"; }

eval "use Net::SSLeay;";
if ( $@ ) {
  print "ok 1 # Skipped: Net::SSLeay is not installed\n"; exit;
}

use Business::OnlinePayment;

my $tx = new Business::OnlinePayment("eSelectPlus");

#$Business::OnlinePayment::HTTPS::DEBUG = 1;
#$Business::OnlinePayment::HTTPS::DEBUG = 1;
#$Business::OnlinePayment::eSelectPlus::DEBUG = 1;
#$Business::OnlinePayment::eSelectPlus::DEBUG = 1;

$tx->content(
    type           => 'VISA',
    login          => 'store1',
    password       => 'yesguy',
    action         => 'Normal Authorization',
    amount         => '32.32',
    card_number    => '4242424242424242',
    expiration     => '08/06',
);
$tx->test_transaction(1); # test, dont really charge
$tx->submit();

if($tx->is_success()) {
    print "not ok 1\n";
} else {
    #warn $tx->server_response."\n";
    #warn  $tx->error_message. "\n";
    print "ok 1\n";
}
