using Payments;

var gateway = new CountingGateway();
var client = new PaymentClient(gateway);
var request = new ChargeRequest(10.00m, "USD", PaymentMethod.NewCard("4242"));
var changedRequest = new ChargeRequest(25.00m, "EUR", PaymentMethod.NewPayPal("ana@example.com"));

var first = client.Charge(request, "order-42");

Check("A second charge with the same key and a different request returns the first receipt and does not call the gateway", () =>
{
    var second = client.Charge(changedRequest, "order-42");
    return (gateway.Count == 1 && first.Equals(second), $"gateway calls {gateway.Count}, receipts {Show(first)} and {Show(second)}");
});

Check("A charge with a new key calls the gateway", () =>
{
    var callsBefore = gateway.Count;
    var other = client.Charge(request, "order-43");
    return (gateway.Count - callsBefore == 1 && other.ChargeId != first.ChargeId, $"gateway calls {gateway.Count - callsBefore}, id {other.ChargeId}");
});

Check("A charge with the first key after a different key returns the first receipt and does not call the gateway", () =>
{
    var callsBefore = gateway.Count;
    var again = client.Charge(request, "order-42");
    return (gateway.Count == callsBefore && again.Equals(first), $"gateway calls {gateway.Count - callsBefore}, receipts {Show(first)} and {Show(again)}");
});

Check("Charges without a key call the gateway each time", () =>
{
    var callsBefore = gateway.Count;
    client.Charge(request);
    client.Charge(request);
    return (gateway.Count - callsBefore == 2, $"gateway calls {gateway.Count - callsBefore}");
});

static void Check(string name, Func<(bool Passed, string Evidence)> body)
{
    var (passed, evidence) = Run(body);
    Console.WriteLine(passed ? $"PASS {name}" : $"FAIL {name} [{evidence}]");
}

static (bool, string) Run(Func<(bool, string)> body)
{
    try { return body(); }
    catch (Exception e) { return (false, $"{e.GetType().Name}: {e.Message.ReplaceLineEndings(" ")}"); }
}

static string Show(Receipt r) => $"({r.ChargeId} {r.Amount} {r.Fee} {r.Total})";

sealed class CountingGateway : IPaymentGateway
{
    public int Count { get; private set; }
    public string Submit(ChargeRequest request, decimal total) => $"id{++Count}";
}
