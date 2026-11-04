using Lib;
using Microsoft.FSharp.Collections;

var point = new Point(1.0, 2.0);
Console.WriteLine($"{Geometry.area(Shape.NewSquare(3.0))} {Geometry.scale(2.0, point).X}");
Console.WriteLine($"{Geometry.count(ListModule.OfSeq(new[] { 1, 2, 3 }))} {new Client(new Store()).Send("hi")} {new Client(new Store()).Total(ListModule.OfSeq(new[] { 4, 5 }))}");

sealed class Store : IStore
{
    public string Get(string key) => key.Length.ToString();
}
