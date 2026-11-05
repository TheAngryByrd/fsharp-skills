using Payments;

var requests = new[] { 1.00m, 2.00m, 3.00m }
    .Select(amount => new ChargeRequest(amount, "USD", PaymentMethod.NewCard("4242")))
    .ToArray();

Check("ChargeAll charges each request of a C# array once, in order, when it is called", client => client.ChargeAll(requests.ToArray()));
Check("ChargeAll charges each request of a List<ChargeRequest> once, in order, when it is called", client => client.ChargeAll(new List<ChargeRequest>(requests)));
Check("ChargeAll charges each request of an IEnumerable<ChargeRequest> iterator once, in order, when it is called", client => client.ChargeAll(Iterate(requests)));

void Check(string name, Func<PaymentClient, IEnumerable<Receipt>> chargeAll)
{
    try { Compare(name, chargeAll); }
    catch (Exception e) { Report(name, false, $"{e.GetType().Name}: {e.Message.ReplaceLineEndings(" ")}"); }
}

void Compare(string name, Func<PaymentClient, IEnumerable<Receipt>> chargeAll)
{
    var expected = requests.Select((r, i) =>
    {
        var fee = Fees.calculate(r.Method, r.Amount);
        return new Receipt($"id{i + 1}", r.Amount, fee, r.Amount + fee);
    }).ToList();
    var expectedCalls = expected.Select(r => (r.Amount, r.Total)).ToList();

    var gateway = new RecordingGateway();
    var receipts = chargeAll(new PaymentClient(gateway));
    var callsBeforeRead = gateway.Calls.Count;
    var first = receipts.ToList();
    var second = receipts.ToList();
    var passed = callsBeforeRead == expected.Count
        && gateway.Calls.SequenceEqual(expectedCalls)
        && first.SequenceEqual(expected)
        && second.SequenceEqual(expected);
    Report(name, passed,
        $"gateway calls before the result is read {callsBeforeRead}, gateway calls [{string.Join(", ", gateway.Calls)}] expected [{string.Join(", ", expectedCalls)}], receipts [{Show(first)}] then [{Show(second)}] expected [{Show(expected)}]");
}

static IEnumerable<ChargeRequest> Iterate(IEnumerable<ChargeRequest> source)
{
    foreach (var request in source) yield return request;
}

static void Report(string name, bool passed, string evidence) =>
    Console.WriteLine(passed ? $"PASS {name}" : $"FAIL {name} [{evidence}]");

static string Show(IEnumerable<Receipt> receipts) =>
    string.Join(", ", receipts.Select(r => $"({r.ChargeId} {r.Amount} {r.Fee} {r.Total})"));

sealed class RecordingGateway : IPaymentGateway
{
    public List<(decimal Amount, decimal Total)> Calls { get; } = new();

    public string Submit(ChargeRequest request, decimal total)
    {
        Calls.Add((request.Amount, total));
        return $"id{Calls.Count}";
    }
}
