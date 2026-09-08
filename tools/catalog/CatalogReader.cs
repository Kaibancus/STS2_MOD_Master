using System.Collections;
using System.Reflection;
using System.Text.Json;
using Environment = System.Environment;
using Godot;
using MegaCrit.Sts2.Core.Models;
using MegaCrit.Sts2.Core.Modding;
using MegaCrit.Sts2.Core.Nodes;

namespace Sts2ModMaster.Catalog;

[ModInitializer(nameof(Initialize))]
public static class CatalogReader
{
    private static readonly List<object> Issues = [];
    private static bool _started;

    public static void Initialize()
    {
        if (_started) throw new InvalidOperationException("Catalog reader invoked twice.");
        _started = true;
        _ = ReadAfterStartup();
    }

    private static async Task ReadAfterStartup()
    {
        try
        {
            if (Environment.UserName != "WDAGUtilityAccount" ||
                Environment.GetEnvironmentVariable("APPDATA") != @"C:\ReportData\profile\roaming")
                throw new InvalidOperationException("This diagnostic is restricted to its reviewed disposable guest.");
            var game = NGame.Instance ?? throw new InvalidOperationException("Native game instance unavailable.");
            await game.GameStartupComplete;
            WriteFacts();
            GD.Print("STS2_CATALOG_FACTS_WRITTEN");
            game.GetTree().Quit();
        }
        catch (Exception error)
        {
            // Never serialize game exception messages, which may contain private paths or expressive text.
            GD.PrintErr("STS2_CATALOG_FAILED " + error.GetType().Name);
            File.WriteAllText(@"C:\ReportData\catalog-error.json",
                JsonSerializer.Serialize(new { errorType = error.GetType().Name, stack = error.StackTrace }));
            NGame.Instance?.GetTree().Quit(1);
        }
    }

    private static PropertyInfo Property(Type type, string name)
    {
        for (Type? current = type; current != null; current = current.BaseType)
        {
            var property = current.GetProperty(name, BindingFlags.Instance | BindingFlags.Public |
                BindingFlags.NonPublic | BindingFlags.DeclaredOnly);
            if (property != null) return property;
        }
        throw new MissingMemberException(type.Name, name);
    }

    private static object? Read(object model, string property)
    {
        try
        {
            var value = Property(model.GetType(), property).GetValue(model);
            if (value is AbstractModel abstractModel) return abstractModel.Id.ToString();
            if (value is Enum) return value.ToString();
            if (value is IEnumerable enumerable && value is not string)
                return enumerable.Cast<object>().Select(v => v.ToString()).ToArray();
            return value;
        }
        catch (TargetInvocationException error)
        {
            Issues.Add(new { model = model.GetType().Name, property,
                error = error.InnerException?.GetType().Name ?? error.GetType().Name });
            return null;
        }
    }

    private static object? Scalar(object model, string property) => Read(model, property);
    private static string Id(AbstractModel model) => model.Id.ToString();
    private static string Entry(AbstractModel model) => model.Id.Entry;

    private static AbstractModel Canonical(Type type, string getter)
    {
        var method = typeof(ModelDb).GetMethods(BindingFlags.Static | BindingFlags.Public)
            .Single(m => m.Name == getter && m.IsGenericMethodDefinition && m.GetParameters().Length == 0);
        return (AbstractModel)method.MakeGenericMethod(type).Invoke(null, null)!;
    }

    private static void WriteFacts()
    {
        var assembly = typeof(CardModel).Assembly;
        var types = assembly.GetTypes();
        var characters = ModelDb.AllCharacters.ToArray();
        var registeredCards = ModelDb.AllCards.Select(Id).ToHashSet();
        var registeredRelics = ModelDb.AllRelics.Select(Id).ToHashSet();
        var activeCardPools = ModelDb.AllCardPools.Select(Id).ToHashSet();
        var activeRelicPools = ModelDb.AllRelicPools.Select(Id).ToHashSet();
        var inventory = new List<object>();
        var cards = new List<object>();
        var relics = new List<object>();
        var cardPools = new List<object>();
        var relicPools = new List<object>();

        foreach (var type in types.Where(t => !t.IsNested &&
            (t.Namespace == "MegaCrit.Sts2.Core.Models.Cards" ||
             t.Namespace == "MegaCrit.Sts2.Core.Models.Cards.Mocks" ||
             t.Namespace == "MegaCrit.Sts2.Core.Models.Relics" ||
             t.Namespace == "MegaCrit.Sts2.Core.Models.Characters" ||
             t.Namespace == "MegaCrit.Sts2.Core.Models.CardPools" ||
             t.Namespace == "MegaCrit.Sts2.Core.Models.RelicPools")).OrderBy(t => t.FullName))
        {
            inventory.Add(new { model = type.Name, category = type.Namespace!.Split('.').Last(),
                isAbstract = type.IsAbstract, isModel = typeof(AbstractModel).IsAssignableFrom(type),
                token = $"0x{type.MetadataToken:X8}" });
            if (type.IsAbstract || !typeof(AbstractModel).IsAssignableFrom(type) ||
                type.Namespace == "MegaCrit.Sts2.Core.Models.Cards.Mocks" ||
                typeof(CharacterModel).IsAssignableFrom(type)) continue;
            if (typeof(CardPoolModel).IsAssignableFrom(type) &&
                type.Name is "DeprivedCardPool" or "MockCardPool" or "DeprecatedCardPool")
            {
                cardPools.Add(new { id = (string?)null, model = type.Name, active = false,
                    cards = (string[]?)null, exclusion = "Explicit test/deprecated pool; do not evaluate its generator." });
                continue;
            }
            if (typeof(RelicPoolModel).IsAssignableFrom(type) && type.Name == "DeprecatedRelicPool")
            {
                relicPools.Add(new { id = (string?)null, model = type.Name, active = false,
                    relics = (string[]?)null, exclusion = "Explicit deprecated pool; do not evaluate its generator." });
                continue;
            }
            string getter = typeof(CardModel).IsAssignableFrom(type) ? "Card" :
                typeof(RelicModel).IsAssignableFrom(type) ? "Relic" :
                typeof(CardPoolModel).IsAssignableFrom(type) ? "CardPool" : "RelicPool";
            AbstractModel model;
            try { model = Canonical(type, getter); }
            catch (TargetInvocationException error)
            {
                Issues.Add(new { model = type.Name, property = "canonical",
                    error = error.InnerException?.GetType().Name ?? error.GetType().Name });
                continue;
            }
            if (model is CardPoolModel pool)
            {
                cardPools.Add(new { id = Id(pool), model = type.Name, active = activeCardPools.Contains(Id(pool)),
                    cards = pool.AllCards.Select(Id).ToArray() });
            }
            else if (model is RelicPoolModel relicPool)
            {
                relicPools.Add(new { id = Id(relicPool), model = type.Name, active = activeRelicPools.Contains(Id(relicPool)),
                    relics = relicPool.AllRelics.Select(Id).ToArray() });
            }
            else if (model is CardModel card)
            {
                cards.Add(new {
                    id = Id(card), entry = Entry(card), model = type.Name,
                    registered = registeredCards.Contains(Id(card)),
                    type = Scalar(card, "Type"), rarity = Scalar(card, "Rarity"), target = Scalar(card, "TargetType"),
                    canonicalEnergy = Scalar(card, "CanonicalEnergyCost"), energyX = Scalar(card, "HasEnergyCostX"),
                    canonicalStars = Scalar(card, "CanonicalStarCost"), starsX = Scalar(card, "HasStarCostX"),
                    playable = Scalar(card, "IsPlayable"), keywords = Scalar(card, "CanonicalKeywords"),
                    library = Scalar(card, "ShouldShowInCardLibrary"),
                    generateCombat = Scalar(card, "CanBeGeneratedInCombat"),
                    generateModifiers = Scalar(card, "CanBeGeneratedByModifiers"),
                    maxUpgradeLevel = Scalar(card, "MaxUpgradeLevel"),
                    pool = Scalar(card, "Pool"), visualPool = Scalar(card, "VisualCardPool"),
                    overriddenCostMethods = type.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
                        .Where(m => m.DeclaringType != typeof(CardModel) && m.DeclaringType != typeof(AbstractModel) &&
                            (m.Name.Contains("Cost") || m.Name.Contains("Energy") || m.Name.Contains("Star")) &&
                            m.IsVirtual && m.GetBaseDefinition() != m).Select(m => m.Name).Order().ToArray()
                });
            }
            else if (model is RelicModel relic)
            {
                relics.Add(new { id = Id(relic), entry = Entry(relic), model = type.Name,
                    registered = registeredRelics.Contains(Id(relic)), rarity = Scalar(relic, "Rarity"),
                    pool = Scalar(relic, "Pool"), allowedInShops = Scalar(relic, "IsAllowedInShops") });
            }
        }
        var result = new {
            schemaVersion = 1, gameVersion = "v0.111.0", gameCommit = "41cef1ea",
            capturedUtc = DateTime.UtcNow.ToString("O"),
            characters = characters.Select(c => new {
                id = Id(c), entry = Entry(c), model = c.GetType().Name,
                playable = Scalar(c, "IsPlayable"), startingHp = Scalar(c, "StartingHp"),
                startingGold = Scalar(c, "StartingGold"), maxEnergy = Scalar(c, "MaxEnergy"),
                orbSlots = Scalar(c, "BaseOrbSlotCount"), showStars = Scalar(c, "ShouldAlwaysShowStarCounter"),
                cardPool = Id(c.CardPool), relicPool = Id(c.RelicPool),
                startingDeck = c.StartingDeck.Select(Id).ToArray(),
                startingRelics = c.StartingRelics.Select(Id).ToArray()
            }).ToArray(),
            cards, relics, cardPools, relicPools, inventory, issues = Issues
        };
        File.WriteAllText(@"C:\ReportData\catalog-raw.json", JsonSerializer.Serialize(result,
            new JsonSerializerOptions { WriteIndented = true }));
    }
}
