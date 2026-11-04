using System.Globalization;
using Microsoft.FSharp.Collections;
using Payments;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

var client = new PaymentClient(new FakeGateway());
var request = new ChargeRequest(40.00m, "USD", PaymentMethod.NewCard("1881"));
var receipt = client.Charge(request);
Console.WriteLine($"{receipt.ChargeId} | fee {receipt.Fee} | total {receipt.Total}");
var batch = client.ChargeAll(ListModule.OfSeq(new[] { request, request }));
Console.WriteLine($"batch {batch.Length} | total {batch.Sum(r => r.Total)}");
Console.WriteLine($"paypal fee {Fees.calculate(PaymentMethod.NewPayPal("bo@example.com"), 50.00m)}");

sealed class FakeGateway : IPaymentGateway
{
    public string Submit(ChargeRequest request, decimal total) => $"cs_{request.Currency}_{total}";
}
