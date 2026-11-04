using Payments;

var gateway = new CountingGateway();
var client = new PaymentClient(gateway);
var request = new ChargeRequest(10.00m, "USD", PaymentMethod.NewCard("4242"));

var fromArray = client.ChargeAll(new[] { request, request, request }).ToList();
Report("ChargeAll charges each request of a C# array", gateway.Count == 3 && fromArray.Count == 3, $"gateway calls {gateway.Count}");

var fromList = client.ChargeAll(new List<ChargeRequest> { request, request }).ToList();
Report("ChargeAll charges each request of a List<ChargeRequest>", gateway.Count == 5 && fromList.Count == 2, $"gateway calls {gateway.Count}");

var fromIterator = client.ChargeAll(Repeat(request, 4)).ToList();
Report("ChargeAll charges each request of an IEnumerable<ChargeRequest> iterator", gateway.Count == 9 && fromIterator.Count == 4, $"gateway calls {gateway.Count}");

static IEnumerable<ChargeRequest> Repeat(ChargeRequest request, int count)
{
    for (var i = 0; i < count; i++) yield return request;
}

static void Report(string name, bool passed, string evidence) =>
    Console.WriteLine(passed ? $"PASS {name}" : $"FAIL {name} [{evidence}]");

sealed class CountingGateway : IPaymentGateway
{
    public int Count { get; private set; }
    public string Submit(ChargeRequest request, decimal total) => $"id{++Count}";
}
