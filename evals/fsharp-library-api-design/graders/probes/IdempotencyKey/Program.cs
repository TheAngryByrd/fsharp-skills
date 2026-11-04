using Payments;

var gateway = new CountingGateway();
var client = new PaymentClient(gateway);
var request = new ChargeRequest(10.00m, "USD", PaymentMethod.NewCard("4242"));

var first = client.Charge(request, "order-42");
var second = client.Charge(request, "order-42");
Report("A second charge with the same key returns the first receipt and does not call the gateway",
    gateway.Count == 1 && first.ChargeId == second.ChargeId && first.Total == second.Total,
    $"gateway calls {gateway.Count}, ids {first.ChargeId} and {second.ChargeId}");

var other = client.Charge(request, "order-43");
Report("A charge with a new key calls the gateway",
    gateway.Count == 2 && other.ChargeId != first.ChargeId,
    $"gateway calls {gateway.Count}, id {other.ChargeId}");

var callsBeforeRepeat = gateway.Count;
var again = client.Charge(request, "order-42");
Report("A charge with the first key after a different key returns the first receipt and does not call the gateway",
    gateway.Count == callsBeforeRepeat && again.ChargeId == first.ChargeId,
    $"gateway calls {gateway.Count - callsBeforeRepeat}, ids {first.ChargeId} and {again.ChargeId}");

var callsBeforeNoKey = gateway.Count;
client.Charge(request);
client.Charge(request);
Report("Charges without a key call the gateway each time", gateway.Count - callsBeforeNoKey == 2, $"gateway calls {gateway.Count - callsBeforeNoKey}");

static void Report(string name, bool passed, string evidence) =>
    Console.WriteLine(passed ? $"PASS {name}" : $"FAIL {name} [{evidence}]");

sealed class CountingGateway : IPaymentGateway
{
    public int Count { get; private set; }
    public string Submit(ChargeRequest request, decimal total) => $"id{++Count}";
}
