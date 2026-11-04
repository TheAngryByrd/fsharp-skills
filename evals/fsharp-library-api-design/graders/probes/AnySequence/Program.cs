using Payments;

var requests = new[] { 1.00m, 2.00m, 3.00m }
    .Select(amount => new ChargeRequest(amount, "USD", PaymentMethod.NewCard("4242")))
    .ToArray();

Check("ChargeAll charges each request of a C# array once, in order, when it is called", client => client.ChargeAll(requests.ToArray()));
Check("ChargeAll charges each request of a List<ChargeRequest> once, in order, when it is called", client => client.ChargeAll(new List<ChargeRequest>(requests)));
Check("ChargeAll charges each request of an IEnumerable<ChargeRequest> iterator once, in order, when it is called", client => client.ChargeAll(Iterate(requests)));

void Check(string name, Func<PaymentClient, IEnumerable<Receipt>> chargeAll)
{
    var gateway = new RecordingGateway();
    var receipts = chargeAll(new PaymentClient(gateway));
    var callsBeforeRead = gateway.Amounts.Count;
    var first = receipts.Select(r => r.Amount).ToList();
    var second = receipts.Select(r => r.Amount).ToList();
    var expected = requests.Select(r => r.Amount).ToList();
    var passed = callsBeforeRead == expected.Count
        && gateway.Amounts.SequenceEqual(expected)
        && first.SequenceEqual(expected)
        && second.SequenceEqual(expected);
    Report(name, passed,
        $"gateway calls before the result is read {callsBeforeRead}, gateway amounts [{string.Join(", ", gateway.Amounts)}], receipt amounts [{string.Join(", ", first)}] then [{string.Join(", ", second)}]");
}

static IEnumerable<ChargeRequest> Iterate(IEnumerable<ChargeRequest> source)
{
    foreach (var request in source) yield return request;
}

static void Report(string name, bool passed, string evidence) =>
    Console.WriteLine(passed ? $"PASS {name}" : $"FAIL {name} [{evidence}]");

sealed class RecordingGateway : IPaymentGateway
{
    public List<decimal> Amounts { get; } = new();

    public string Submit(ChargeRequest request, decimal total)
    {
        Amounts.Add(request.Amount);
        return $"id{Amounts.Count}";
    }
}
