using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

public sealed class OrderLine
{
    public string Sku { get; init; } = "";
    public int Quantity { get; init; }
    public decimal UnitPrice { get; init; }
    public bool InStock { get; init; }
}

public sealed class Order
{
    public string Id { get; init; } = "";
    public string Customer { get; init; } = "";
    public string DiscountCode { get; init; } = "";
    public List<OrderLine> Lines { get; init; } = new();
}

public static class OrderReport
{
    public static (decimal Subtotal, decimal Discount, int ItemCount) ComputeTotals(Order order)
    {
        decimal subtotal = 0m;
        int itemCount = 0;
        foreach (var line in order.Lines)
        {
            subtotal += line.Quantity * line.UnitPrice;
            itemCount += line.Quantity;
        }

        decimal discount = 0m;
        if (TryGetDiscountRate(order.DiscountCode, out var rate))
        {
            discount = Math.Round(subtotal * rate, 2);
        }

        return (subtotal, discount, itemCount);
    }

    public static bool TryGetDiscountRate(string code, out decimal rate)
    {
        if (code == "SAVE10")
        {
            rate = 0.10m;
            return true;
        }
        else if (code == "SAVE25")
        {
            rate = 0.25m;
            return true;
        }
        else if (code == "STAFF")
        {
            rate = 0.40m;
            return true;
        }

        rate = 0m;
        return false;
    }

    public static string Tier(decimal total)
    {
        if (total >= 1000m) return "gold";
        else if (total >= 250m) return "silver";
        else return "bronze";
    }

    public static OrderLine? FirstBackordered(Order order)
    {
        foreach (var line in order.Lines)
        {
            if (!line.InStock) return line;
        }

        return null;
    }

    public static string Render(Order order)
    {
        var inv = CultureInfo.InvariantCulture;
        var totals = ComputeTotals(order);
        var total = totals.Subtotal - totals.Discount;
        var sb = new StringBuilder();
        sb.Append($"Order {order.Id} for {order.Customer}\n");
        for (int i = 0; i < order.Lines.Count; i++)
        {
            var line = order.Lines[i];
            sb.Append($"{i + 1}. {line.Sku} x{line.Quantity} @ {line.UnitPrice.ToString("0.00", inv)}\n");
        }

        sb.Append($"Items: {totals.ItemCount}\n");
        sb.Append($"Subtotal: {totals.Subtotal.ToString("0.00", inv)}\n");
        if (totals.Discount > 0m)
        {
            sb.Append($"Discount: -{totals.Discount.ToString("0.00", inv)}\n");
        }

        sb.Append($"Total: {total.ToString("0.00", inv)} ({Tier(total)})\n");
        var backordered = FirstBackordered(order);
        if (backordered != null)
        {
            sb.Append($"Backordered: {backordered.Sku}\n");
        }

        return sb.ToString();
    }
}
