"""Deterministic fixtures for checking the real MarketSense Lua evaluator."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from .bridge import run_lua, run_lua_result
from .models import ItemDefinition, WorkshopMod


def mock_definitions() -> list[ItemDefinition]:
    """Return stable fixtures that exercise the real evaluator, not a clone."""
    fixture_mod = WorkshopMod(
        root=Path("<offline-fixture>"),
        workshop_id="fixture",
        mod_id="MarketSenseFixture",
        name="MarketSense offline fixture",
        source_kind="fixture",
    )

    def make(name: str, props: dict[str, Any]) -> ItemDefinition:
        return ItemDefinition(
            full_type=f"MarketSenseFixture.{name}",
            module="MarketSenseFixture",
            props=props,
            mod=fixture_mod,
            script_path="<offline-fixture>",
        )

    return [
        make("FoodLow", {
            "itemType": "Food", "displayCategory": "Food", "foodType": "Meat",
            "hungerChange": -0.05, "calories": 50, "daysFresh": 1, "daysRotten": 2,
            "actualWeight": 0.2, "description": "a small portion of meat",
            "canSpawnAsLoot": True,
        }),
        make("FoodHigh", {
            "itemType": "Food", "displayCategory": "Food", "foodType": "Meat",
            "hungerChange": -0.8, "calories": 800, "daysFresh": 10, "daysRotten": 20,
            "actualWeight": 0.2, "description": "a large portion of meat",
            "canSpawnAsLoot": True,
        }),
        make("CannedMeal", {
            "itemType": "Food", "displayCategory": "Food", "hungerChange": -0.2,
            "calories": 250, "daysFresh": 20, "daysRotten": 40, "actualWeight": 0.5,
            "description": "Canned preserved bean meal", "isCraftRecipeProduct": True,
        }),
        make("VanillaReceipt", {
            "itemType": "base:literature", "displayCategory": "Junk",
            "tags": ["base:uninteresting"], "readType": "photo",
            "description": "a small receipt", "canSpawnAsLoot": True,
        }),
        make("NarcoticsSeedPacket", {
            "itemType": "Base:Literature", "displayCategory": "Drugs",
            "tags": ["Base:FastRead"], "readType": "photo",
            "learnedRecipes": "Weed Growing Season", "isCraftRecipeProduct": True,
            "description": "a packet of growing seeds", "canSpawnAsLoot": True,
        }),
        ItemDefinition(
            full_type="Base.Flier_Nolans", module="Base",
            props={
                "itemType": "base:literature", "displayCategory": "Junk",
                "tags": ["base:fastread", "base:picture"], "readType": "photo",
            }, mod=fixture_mod, script_path="<offline-fixture>",
        ),
        make("Bandage", {
            "displayCategory": "FirstAid", "bandagePower": 1, "actualWeight": 0.1,
            "description": "sterile medical dressing", "canBeForaged": True,
        }),
        make("Axe", {
            "itemType": "Weapon", "displayCategory": "Weapon", "weaponCategories": ["Axe"],
            "minDamage": 1, "maxDamage": 2, "maxRange": 1, "conditionMax": 10,
            "actualWeight": 1.5, "description": "a heavy hand axe", "canSpawnAsLoot": True,
        }),
        make("Spear", {
            "itemType": "base:weapon", "displayCategory": "WeaponCrafted",
            "weaponCategories": ["base:improvised", "base:spear"],
            "tags": ["base:fishingspear"], "minDamage": 1, "maxDamage": 1.6,
            "maxRange": 1.5, "conditionMax": 8, "actualWeight": 1.2,
            "description": "a crafted fishing spear", "canSpawnAsLoot": True,
        }),
        make("SpearTagFallback", {
            "itemType": "base:weapon", "displayCategory": "Weapon",
            "tags": ["base:fishingspear"], "minDamage": 1, "maxDamage": 1.4,
            "maxRange": 1.5, "conditionMax": 8, "actualWeight": 1.1,
            "description": "a Workshop spear without a Categories field",
            "canSpawnAsLoot": True,
        }),
        make("Bag", {
            "itemType": "Container", "displayCategory": "Bag",
            "capacity": 20, "weightReduction": 80,
            "actualWeight": 1, "description": "a canvas carrying bag", "canSpawnAsLoot": True,
        }),
        make("Backpack", {
            "itemType": "Container", "displayCategory": "Bag",
            "canBeEquipped": "base:back", "capacity": 20, "weightReduction": 80,
            "actualWeight": 1, "description": "a canvas backpack", "canSpawnAsLoot": True,
        }),
        make("Satchel", {
            "itemType": "Container", "displayCategory": "Bag",
            "bodyLocation": "base:satchel", "canBeEquipped": "base:satchel",
            "capacity": 12, "weightReduction": 65, "actualWeight": 0.8,
            "description": "a worn satchel", "canSpawnAsLoot": True,
        }),
        make("FannyPackFront", {
            "itemType": "Container", "displayCategory": "Bag",
            "bodyLocation": "base:fannypackfront", "canBeEquipped": "base:fannypackfront",
            "capacity": 2, "weightReduction": 85, "actualWeight": 0.2,
            "description": "a front fanny pack", "canSpawnAsLoot": True,
        }),
        make("FannyPackBack", {
            "itemType": "Container", "displayCategory": "Bag",
            "bodyLocation": "base:fannypackback", "canBeEquipped": "base:fannypackback",
            "capacity": 2, "weightReduction": 85, "actualWeight": 0.2,
            "description": "a back fanny pack", "canSpawnAsLoot": True,
        }),
        make("Bandolier", {
            "itemType": "Container", "displayCategory": "Bag",
            "bodyLocation": "base:webbing", "canBeEquipped": "base:webbing",
            "capacity": 6, "weightReduction": 80, "actualWeight": 0.4,
            "description": "a webbing bandolier", "canSpawnAsLoot": True,
        }),
        make("Duffel", {
            "itemType": "Container", "displayCategory": "Bag",
            "canBeEquipped": "base:back", "worldStaticModel": "DuffelBag_Ground",
            "capacity": 25, "weightReduction": 65, "actualWeight": 1.2,
            "description": "a duffel bag", "canSpawnAsLoot": True,
        }),
        make("LooseBag", {
            "itemType": "Container", "displayCategory": "Container",
            "capacity": 10, "actualWeight": 0.3,
            "description": "a loose laundry bag that is not wearable", "canSpawnAsLoot": True,
        }),
        make("Television", {
            "itemType": "base:radio", "displayCategory": "Communications",
            "icon": "Television", "worldObjectSprite": "appliances_television_01_4",
            "description": "a television", "canSpawnAsLoot": True,
        }),
        make("Radio", {
            "itemType": "base:radio", "displayCategory": "Communications",
            "icon": "Radio", "description": "a portable radio", "canSpawnAsLoot": True,
        }),
        make("SleepingBag", {
            "itemType": "base:moveable", "displayCategory": "Camping",
            "tags": ["base:tentbed", "base:isfirefuel"],
            "icon": "Sleepingbag3_Open", "worldObjectSprite": "camping_02_8",
            "description": "Tooltip_item_NeedsPackedSleepingBag", "canSpawnAsLoot": True,
        }),
        make("Mattress", {
            "itemType": "base:moveable", "displayCategory": "Furniture",
            "tags": ["base:tentbed"], "icon": "Mattress",
            "worldObjectSprite": "carpentry_02_76", "description": "Tooltip_item_Mattress",
            "canSpawnAsLoot": True,
        }),
        make("GymnMat", {
            "itemType": "base:moveable", "displayCategory": "Furniture",
            "tags": ["base:tentbed"], "icon": "default",
            "worldObjectSprite": "recreational_sports_01_35", "description": "Tooltip_item_Mattress",
            "canSpawnAsLoot": True,
        }),
        make("Tent", {
            "itemType": "base:moveable", "displayCategory": "Camping",
            "tags": ["base:isfirefuel", "base:isfiretinder"],
            "icon": "Tent1_Open", "worldObjectSprite": "camping_04_32",
            "description": "Tooltip_item_NeedsPackedTent", "canSpawnAsLoot": True,
        }),
        make("MoveableLamp", {
            "itemType": "base:moveable", "displayCategory": "Furniture",
            "icon": "default", "worldObjectSprite": "lighting_indoor_01_8",
            "spriteProperties": {
                "CustomName": "Lamp", "GroupName": "Striped", "IsTableTop": True,
                "Material": "Electric", "Surface": 34,
            },
            "description": "a moveable table lamp", "canSpawnAsLoot": True,
        }),
        make("InstalledLamp", {
            "itemType": "base:moveable", "displayCategory": "Lighting",
            "icon": "ui_lighting_indoor_01_56", "worldObjectSprite": "lighting_indoor_01_56",
            "spriteProperties": {
                "CustomName": "Lamp", "GroupName": "Indoor", "IsTableTop": True,
                "Material": "Electric", "Surface": 34,
            },
            "description": "a floor lamp", "canSpawnAsLoot": True,
        }),
        make("Flashlight", {
            "itemType": "base:drainable", "displayCategory": "LightSource",
            "tags": ["base:flashlight", "base:flashlightpillar"],
            "icon": "FlashlightAngled_Black", "description": "a battery-powered flashlight",
            "canSpawnAsLoot": True,
        }),
        make("GunLight", {
            "itemType": "base:weaponpart", "displayCategory": "WeaponPart",
            "tags": ["base:flashlight", "base:usesbattery"], "icon": "Flashlight2",
            "partType": "Canon", "mountOn": "Base.Pistol", "canSpawnAsLoot": True,
        }),
        make("MoveableTannedHide", {
            "itemType": "base:moveable", "displayCategory": "Material",
            "tags": ["base:leatherfurtannedsmall"], "icon": "Leather_Brown_Small",
            "worldObjectSprite": "rugs_animals_88", "description": "a tanned hide",
            "canSpawnAsLoot": True,
        }),
        make("Wallpaper", {
            "itemType": "base:drainable", "displayCategory": "Material",
            "tags": ["base:wallpaper"], "useDelta": 0.1,
            "worldStaticModel": "Wallpaper_GreenDiamond",
            "description": "a roll of wallpaper", "canSpawnAsLoot": True,
        }),
        make("ConcretePowder", {
            "itemType": "base:normal", "displayCategory": "Material",
            "worldStaticModel": "BagofConcretePowder",
            "description": "a bag of concrete powder", "canSpawnAsLoot": True,
        }),
        make("ClayBrick", {
            "itemType": "base:normal", "displayCategory": "Material",
            "worldStaticModel": "ClayBrick",
            "description": "a clay brick", "canSpawnAsLoot": True,
        }),
        make("PotteryClayPot", {
            "itemType": "base:normal", "displayCategory": "Material",
            "worldStaticModel": "ClayPot",
            "description": "an unfired clay pot", "canSpawnAsLoot": True,
        }),
        make("MetalOre", {
            "itemType": "base:normal", "displayCategory": "Material",
            "tags": ["base:hasmetal", "base:ironore", "base:ironsource"],
            "worldStaticModel": "IronOre", "description": "iron ore",
            "canSpawnAsLoot": True,
        }),
        make("HardwareNails", {
            "itemType": "base:normal", "displayCategory": "Material",
            "tags": ["base:hasmetal"], "worldStaticModel": "Nails",
            "description": "a box of nails", "canSpawnAsLoot": True,
        }),
        make("TailoringRope", {
            "itemType": "base:normal", "displayCategory": "Material",
            "tags": ["base:rope"], "worldStaticModel": "Rope_Looped",
            "description": "a coil of rope", "canSpawnAsLoot": True,
        }),
        make("FirewoodBundle", {
            "itemType": "base:normal", "displayCategory": "Material",
            "tags": ["base:isfirefuel"], "doubleClickRecipe": "UnbundleFirewood",
            "worldStaticModel": "FirewoodBundle", "description": "a bundle of firewood",
            "canSpawnAsLoot": True,
        }),
        make("GlassPanel", {
            "itemType": "base:normal", "displayCategory": "Material",
            "tags": ["base:glass"], "worldStaticModel": "GlassPanel",
            "description": "a pane of glass", "canSpawnAsLoot": True,
        }),
        make("StoneMaterial", {
            "itemType": "base:normal", "displayCategory": "Material",
            "tags": ["base:limestone"], "worldStaticModel": "Limestone",
            "description": "a piece of limestone", "canSpawnAsLoot": True,
        }),
        make("Gunpowder", {
            "itemType": "base:normal", "displayCategory": "Material",
            "worldStaticModel": "GunpowderJar", "description": "gunpowder",
            "canSpawnAsLoot": True,
        }),
        make("PackFrame", {
            "itemType": "base:normal", "displayCategory": "Material",
            "tags": ["base:hasmetal"], "worldStaticModel": "CraftedFrame_Lrg2_Grnd",
            "description": "a crafted pack frame", "canSpawnAsLoot": True,
        }),
        make("WoodMaterial", {
            "itemType": "base:normal", "displayCategory": "Material",
            "tags": ["base:wood"], "worldStaticModel": "WoodChunk",
            "description": "a piece of wood", "canSpawnAsLoot": True,
        }),
        make("UnknownBundle", {
            "itemType": "base:normal", "displayCategory": "Material",
            "worldStaticModel": "UnknownBundle", "description": "a bundled material",
            "canSpawnAsLoot": True,
        }),
        make("GenericMaterial", {
            "itemType": "base:normal", "displayCategory": "Material",
            "worldStaticModel": "UnidentifiedMaterial", "description": "an unusual material",
            "canSpawnAsLoot": True,
        }),
        make("ToiletPaper", {
            "itemType": "base:drainable", "displayCategory": "Junk",
            "icon": "ToiletPaper", "worldStaticModel": "ToiletPaper",
            "description": "Tooltip_tissue_tooltip", "canSpawnAsLoot": True,
        }),
        make("NoveltySkullGlasses", {
            "itemType": "base:clothing", "displayCategory": "Memento",
            "bodyLocation": "base:eyes", "tags": ["base:ismemento"],
            "icon": "Glasses_Novelty_HoloSkulls",
            "description": "novelty skull glasses", "canSpawnAsLoot": True,
        }),
        make("AnimalHead", {
            "itemType": "base:normal", "displayCategory": "AnimalPart",
            "tags": ["base:animalhead"], "worldStaticModel": "Cow_Head_Black",
            "description": "an animal head", "canSpawnAsLoot": True,
        }),
        make("MoveableBrokenGlass", {
            "itemType": "base:moveable", "displayCategory": "Junk",
            "tags": ["base:brokenglass"], "icon": "BrokenGlass",
            "worldObjectSprite": "brokenglass_1_0", "description": "broken glass",
            "canSpawnAsLoot": True,
        }),
        make("MoveableSink", {
            "itemType": "base:moveable", "displayCategory": "Furniture",
            "worldObjectSprite": "fixtures_sinks_01_9", "description": "a kitchen sink",
            "spriteProperties": {
                "CustomName": "Sink", "GroupName": "Chrome", "IsTableTop": True,
                "Material": "Plumbing", "Material2": "Pipes", "Material3": "Sink",
                "waterPiped": True, "Surface": 34,
            },
            "canSpawnAsLoot": True,
        }),
        make("ComboWasherDryer", {
            "itemType": "base:moveable", "displayCategory": "Furniture",
            "worldObjectSprite": "appliances_laundry_01_0",
            "spriteProperties": {
                "CustomName": "Combo Washer Dryer", "GroupName": "Blue",
                "IsoType": "IsoCombinationWasherDryer", "Material3": "Electric",
                "container": "clothingwasher", "ContainerCapacity": 20,
                "Surface": 38, "IsTable": True,
            },
            "description": "a powered washer and dryer", "canSpawnAsLoot": True,
        }),
        make("LaundryBin", {
            "itemType": "base:moveable", "displayCategory": "Furniture",
            "worldObjectSprite": "appliances_laundry_01_24",
            "spriteProperties": {
                "CustomName": "Bin", "GroupName": "Washing",
                "Material": "Fabric", "Material2": "MetalBars",
                "container": "clothingdryerbasic", "ContainerCapacity": 20,
            },
            "description": "a laundry bin", "canSpawnAsLoot": True,
        }),
        make("LightRoundTable", {
            "itemType": "base:moveable", "displayCategory": "Furniture",
            "worldObjectSprite": "furniture_tables_high_01_7",
            "spriteProperties": {
                "CustomName": "Light Round Table", "GenericCraftingSurface": True,
                "IsTable": True, "Material": "Wood", "Surface": 27,
            },
            "description": "a light round table", "canSpawnAsLoot": True,
        }),
        make("Counter", {
            "itemType": "base:moveable", "displayCategory": "Furniture",
            "worldObjectSprite": "fixtures_counters_01_5",
            "spriteProperties": {
                "CustomName": "Counter", "GroupName": "Modern",
                "container": "counter", "GenericCraftingSurface": True,
                "IsTable": True, "Material": "Wood", "Surface": 35,
            },
            "description": "a kitchen counter", "canSpawnAsLoot": True,
        }),
        make("Drawers", {
            "itemType": "base:moveable", "displayCategory": "Furniture",
            "worldObjectSprite": "furniture_storage_01_9",
            "spriteProperties": {
                "CustomName": "Drawers", "GroupName": "Fancy",
                "container": "dresser", "ContainerCapacity": 20,
                "IsTable": True, "Material": "Wood", "Surface": 34,
            },
            "description": "a chest of drawers", "canSpawnAsLoot": True,
        }),
        make("MilitaryCrate", {
            "itemType": "base:moveable", "displayCategory": "Furniture",
            "worldObjectSprite": "location_military_generic_01_1",
            "spriteProperties": {
                "CustomName": "Crate", "GroupName": "Military",
                "container": "militarycrate", "ContainerCapacity": 50,
                "IsTable": True, "Material": "MetalPlates", "Surface": 32,
            },
            "description": "a military storage crate", "canSpawnAsLoot": True,
        }),
        make("Dishwasher", {
            "itemType": "base:moveable", "displayCategory": "Furniture",
            "worldObjectSprite": "appliances_cooking_01_77",
            "spriteProperties": {
                "CustomName": "Dishwasher", "GroupName": "Metal",
                "container": "dishwasher", "ContainerCapacity": 10,
                "GenericCraftingSurface": True, "IsTable": True,
                "Material": "Fridge", "Material2": "Electric",
            },
            "description": "an electric dishwasher", "canSpawnAsLoot": True,
        }),
        make("GardenSeed", {
            "itemType": "base:normal", "displayCategory": "Gardening",
            "tags": ["base:isseed"], "icon": "Seeds_Generic",
            "worldStaticModel": "Seeds_Generic", "isCraftRecipeProduct": True,
            "description": "a packet of loose vegetable seeds",
            "canSpawnAsLoot": True, "canBeForaged": True,
        }),
        make("Compost", {
            "itemType": "base:drainable", "displayCategory": "Gardening",
            "tags": ["base:compost"], "tooltip": "Tooltip_Fertilizer",
            "worldStaticModel": "CompostBag", "description": "compost",
            "canSpawnAsLoot": True,
        }),
        make("Fertilizer", {
            "itemType": "base:drainable", "displayCategory": "Gardening",
            "tags": ["base:fertilizer"], "tooltip": "Tooltip_Fertilizer",
            "worldStaticModel": "Fertilizer_Ground", "description": "fertilizer",
            "canSpawnAsLoot": True,
        }),
        make("SlugRepellent", {
            "itemType": "base:drainable", "displayCategory": "Gardening",
            "worldStaticModel": "SlugRepellent", "description": "slug repellent",
            "canSpawnAsLoot": True,
        }),
        make("FitnessContraption", {
            "itemType": "base:moveable", "displayCategory": "Furniture",
            "worldObjectSprite": "recreational_sports_01_41",
            "spriteProperties": {
                "CustomName": "Contraption", "GroupName": "Fitness",
                "IsMoveAble": True, "PickUpWeight": 200,
            },
            "description": "a fitness contraption", "canSpawnAsLoot": True,
        }),
        make("KickDrum", {
            "itemType": "base:moveable", "displayCategory": "Furniture",
            "worldObjectSprite": "recreational_01_64",
            "spriteProperties": {
                "CustomName": "Drum", "GroupName": "Kick", "MaterialType": "Metal_Light",
            },
            "description": "a kick drum", "canSpawnAsLoot": True,
        }),
        make("WallClock", {
            "itemType": "base:moveable", "displayCategory": "Furniture",
            "worldObjectSprite": "location_community_school_01_32",
            "spriteProperties": {
                "CustomName": "Clock", "GroupName": "Wall", "Material": "Electric",
                "MoveType": "WallObject",
            },
            "description": "a wall clock", "canSpawnAsLoot": True,
        }),
        make("Gurney", {
            "itemType": "base:moveable", "displayCategory": "Furniture",
            "worldObjectSprite": "location_community_medical_01_72",
            "spriteProperties": {
                "CustomName": "Bed", "GroupName": "Hospital", "BedType": "averageBed",
            },
            "description": "a hospital gurney", "canSpawnAsLoot": True,
        }),
        make("ConcreteMixer", {
            "itemType": "base:moveable", "displayCategory": "Furniture",
            "worldObjectSprite": "construction_01_6",
            "spriteProperties": {
                "CustomName": "Grinder", "GroupName": "Mortar",
                "Material": "SmallMetalPlates", "Material2": "MetalBars",
            },
            "description": "a concrete mixer", "canSpawnAsLoot": True,
        }),
        make("SkillBook", {
            "itemType": "base:normal", "displayCategory": "SkillBook",
            "description": "a mechanics skill book", "canSpawnAsLoot": True,
        }),
        make("CartographyMap", {
            "itemType": "base:map", "displayCategory": "Cartography",
            "description": "a map of the town", "canSpawnAsLoot": True,
        }),
        make("WeaponPart", {
            "itemType": "base:weaponpart", "displayCategory": "WeaponPart",
            "description": "a weapon component", "canSpawnAsLoot": True,
        }),
        make("WaterContainer", {
            "itemType": "base:normal", "displayCategory": "WaterContainer",
            "canStoreWater": True, "capacity": 10, "description": "an empty bucket",
            "canSpawnAsLoot": True,
        }),
        make("ProtectiveGorget", {
            "itemType": "base:clothing", "displayCategory": "ProtectiveGear",
            "bodyLocation": "Gorget", "description": "a protective neck guard",
            "canSpawnAsLoot": True,
        }),
        make("DebugDummy", {
            "displayCategory": "Hidden", "displayName": "DUMMY ITEM", "hidden": True,
            "canSpawnAsLoot": True,
        }),
    ]


def self_test(lua: str) -> tuple[bool, list[dict[str, Any]]]:
    rows = run_lua(lua, mock_definitions())
    by_type = {row.get("fullType"): row for row in rows}
    checks: list[dict[str, Any]] = []

    def check(name: str, passed: bool, detail: str) -> None:
        checks.append({"name": name, "passed": bool(passed), "detail": detail})

    expected_types = {
        "MarketSenseFixture.FoodLow", "MarketSenseFixture.FoodHigh",
        "MarketSenseFixture.CannedMeal", "MarketSenseFixture.VanillaReceipt",
        "MarketSenseFixture.NarcoticsSeedPacket", "MarketSenseFixture.Bandage",
        "Base.Flier_Nolans",
        "MarketSenseFixture.Axe", "MarketSenseFixture.Bag",
        "MarketSenseFixture.Spear",
        "MarketSenseFixture.SpearTagFallback",
        "MarketSenseFixture.Backpack", "MarketSenseFixture.Satchel",
        "MarketSenseFixture.FannyPackFront", "MarketSenseFixture.FannyPackBack",
        "MarketSenseFixture.Bandolier", "MarketSenseFixture.Duffel",
        "MarketSenseFixture.LooseBag",
        "MarketSenseFixture.Television", "MarketSenseFixture.MoveableSink",
        "MarketSenseFixture.Radio",
        "MarketSenseFixture.Wallpaper", "MarketSenseFixture.ConcretePowder",
        "MarketSenseFixture.ClayBrick", "MarketSenseFixture.PotteryClayPot",
        "MarketSenseFixture.MetalOre", "MarketSenseFixture.HardwareNails",
        "MarketSenseFixture.TailoringRope", "MarketSenseFixture.FirewoodBundle",
        "MarketSenseFixture.GlassPanel", "MarketSenseFixture.StoneMaterial",
        "MarketSenseFixture.Gunpowder", "MarketSenseFixture.PackFrame",
        "MarketSenseFixture.WoodMaterial", "MarketSenseFixture.UnknownBundle",
        "MarketSenseFixture.GenericMaterial",
        "MarketSenseFixture.ToiletPaper",
        "MarketSenseFixture.NoveltySkullGlasses",
        "MarketSenseFixture.AnimalHead",
        "MarketSenseFixture.SleepingBag", "MarketSenseFixture.Tent",
        "MarketSenseFixture.Mattress", "MarketSenseFixture.GymnMat",
        "MarketSenseFixture.MoveableLamp", "MarketSenseFixture.InstalledLamp",
        "MarketSenseFixture.Flashlight", "MarketSenseFixture.GunLight",
        "MarketSenseFixture.MoveableTannedHide", "MarketSenseFixture.MoveableBrokenGlass",
        "MarketSenseFixture.SkillBook", "MarketSenseFixture.CartographyMap",
        "MarketSenseFixture.WeaponPart", "MarketSenseFixture.WaterContainer",
        "MarketSenseFixture.ProtectiveGorget",
        "MarketSenseFixture.ComboWasherDryer", "MarketSenseFixture.LaundryBin",
        "MarketSenseFixture.LightRoundTable", "MarketSenseFixture.Counter",
        "MarketSenseFixture.Drawers", "MarketSenseFixture.MilitaryCrate",
        "MarketSenseFixture.Dishwasher", "MarketSenseFixture.GardenSeed",
        "MarketSenseFixture.Compost", "MarketSenseFixture.Fertilizer",
        "MarketSenseFixture.SlugRepellent", "MarketSenseFixture.FitnessContraption",
        "MarketSenseFixture.KickDrum", "MarketSenseFixture.WallClock",
        "MarketSenseFixture.Gurney", "MarketSenseFixture.ConcreteMixer",
        "MarketSenseFixture.DebugDummy",
    }
    check(
        "all fixture rows evaluated",
        set(by_type) == expected_types and all(not row.get("error") for row in rows),
        f"{len(rows)}/{len(expected_types)} rows, errors={sum(1 for row in rows if row.get('error'))}",
    )

    expected_categories = {
        "MarketSenseFixture.FoodLow": "Food",
        "MarketSenseFixture.FoodHigh": "Food",
        "MarketSenseFixture.CannedMeal": "Food",
        "MarketSenseFixture.VanillaReceipt": "Literature",
        "MarketSenseFixture.NarcoticsSeedPacket": "Building",
        "Base.Flier_Nolans": "Literature",
        "MarketSenseFixture.Bandage": "Medical",
        "MarketSenseFixture.Axe": "Weapon",
        "MarketSenseFixture.Spear": "Weapon",
        "MarketSenseFixture.SpearTagFallback": "Weapon",
        "MarketSenseFixture.Bag": "Container",
        "MarketSenseFixture.Backpack": "Container",
        "MarketSenseFixture.Satchel": "Container",
        "MarketSenseFixture.FannyPackFront": "Container",
        "MarketSenseFixture.FannyPackBack": "Container",
        "MarketSenseFixture.Bandolier": "Container",
        "MarketSenseFixture.Duffel": "Container",
        "MarketSenseFixture.LooseBag": "Container",
        "MarketSenseFixture.Television": "Electronics",
        "MarketSenseFixture.Radio": "Electronics",
        "MarketSenseFixture.Wallpaper": "Resource",
        "MarketSenseFixture.ConcretePowder": "Resource",
        "MarketSenseFixture.ClayBrick": "Resource",
        "MarketSenseFixture.PotteryClayPot": "Resource",
        "MarketSenseFixture.MetalOre": "Resource",
        "MarketSenseFixture.HardwareNails": "Resource",
        "MarketSenseFixture.TailoringRope": "Resource",
        "MarketSenseFixture.FirewoodBundle": "Resource",
        "MarketSenseFixture.GlassPanel": "Resource",
        "MarketSenseFixture.StoneMaterial": "Resource",
        "MarketSenseFixture.Gunpowder": "Resource",
        "MarketSenseFixture.PackFrame": "Resource",
        "MarketSenseFixture.WoodMaterial": "Resource",
        "MarketSenseFixture.UnknownBundle": "Resource",
        "MarketSenseFixture.GenericMaterial": "Resource",
        "MarketSenseFixture.ToiletPaper": "Resource",
        "MarketSenseFixture.NoveltySkullGlasses": "Misc",
        "MarketSenseFixture.AnimalHead": "Resource",
        "MarketSenseFixture.SleepingBag": "Building",
        "MarketSenseFixture.Tent": "Building",
        "MarketSenseFixture.Mattress": "Building",
        "MarketSenseFixture.GymnMat": "Building",
        "MarketSenseFixture.MoveableLamp": "Building",
        "MarketSenseFixture.InstalledLamp": "Building",
        "MarketSenseFixture.Flashlight": "Electronics",
        "MarketSenseFixture.GunLight": "Weapon",
        "MarketSenseFixture.MoveableTannedHide": "Resource",
        "MarketSenseFixture.MoveableBrokenGlass": "Misc",
        "MarketSenseFixture.MoveableSink": "Building",
        "MarketSenseFixture.SkillBook": "Literature",
        "MarketSenseFixture.CartographyMap": "Literature",
        "MarketSenseFixture.WeaponPart": "Weapon",
        "MarketSenseFixture.WaterContainer": "Container",
        "MarketSenseFixture.ProtectiveGorget": "Clothing",
        "MarketSenseFixture.ComboWasherDryer": "Electronics",
        "MarketSenseFixture.LaundryBin": "Building",
        "MarketSenseFixture.LightRoundTable": "Building",
        "MarketSenseFixture.Counter": "Building",
        "MarketSenseFixture.Drawers": "Building",
        "MarketSenseFixture.MilitaryCrate": "Building",
        "MarketSenseFixture.Dishwasher": "Electronics",
        "MarketSenseFixture.GardenSeed": "Building",
        "MarketSenseFixture.Compost": "Building",
        "MarketSenseFixture.Fertilizer": "Building",
        "MarketSenseFixture.SlugRepellent": "Building",
        "MarketSenseFixture.FitnessContraption": "Building",
        "MarketSenseFixture.KickDrum": "Building",
        "MarketSenseFixture.WallClock": "Electronics",
        "MarketSenseFixture.Gurney": "Building",
        "MarketSenseFixture.ConcreteMixer": "Building",
        "MarketSenseFixture.DebugDummy": "Misc",
    }
    category_ok = all(
        by_type.get(item, {}).get("category") == category
        for item, category in expected_categories.items()
    )
    check(
        "root categories",
        category_ok,
        ", ".join(
            f"{item.rsplit('.', 1)[-1]}={by_type.get(item, {}).get('category', '?')}"
            for item in sorted(expected_categories)
        ),
    )

    receipt = by_type.get("MarketSenseFixture.VanillaReceipt", {})
    receipt_detection = receipt.get("detection") or {}
    check(
        "vanilla junk literature is not a photo",
        (
            receipt.get("primary") == "LiteratureOrJunk"
            and receipt_detection.get("resolverSource") == "root_literature"
            and (receipt_detection.get("classifier") or {}).get("details", {}).get("source")
            == "lit_uninteresting"
        ),
        f"primary={receipt.get('primary', '?')} source="
        f"{((receipt_detection.get('classifier') or {}).get('details') or {}).get('source', '?')}",
    )

    flier = by_type.get("Base.Flier_Nolans", {})
    check(
        "vanilla flier uses its explicit literature subtype",
        flier.get("primary") == "LiteratureFlier",
        f"primary={flier.get('primary', '?')} source={flier.get('source', '?')}",
    )

    seed = by_type.get("MarketSenseFixture.NarcoticsSeedPacket", {})
    seed_context = seed.get("context") or {}
    seed_detection = seed.get("detection") or {}
    check(
        "literature-backed seed packet is gardening stock",
        (
            seed.get("category") == "Building"
            and seed.get("primary") == "GardeningSeedPacket"
            and seed_detection.get("root") == "Building"
            and (seed_detection.get("classifier") or {}).get("signature") == "Gardening"
            and seed_context.get("learnedRecipes") == ["Weed Growing Season"]
        ),
        f"category={seed.get('category', '?')} primary={seed.get('primary', '?')} "
        f"root={seed_detection.get('root', '?')} recipes={seed_context.get('learnedRecipes', '?')}",
    )

    expected_primary = {
        "MarketSenseFixture.Bag": "ContainerBag",
        "MarketSenseFixture.Spear": "WeaponSpear",
        "MarketSenseFixture.SpearTagFallback": "WeaponSpear",
        "MarketSenseFixture.Backpack": "ContainerBagBackpack",
        "MarketSenseFixture.Satchel": "ContainerBagSatchel",
        "MarketSenseFixture.FannyPackFront": "ContainerBagFanny",
        "MarketSenseFixture.FannyPackBack": "ContainerBagFanny",
        "MarketSenseFixture.Bandolier": "ContainerBagBandolier",
        "MarketSenseFixture.Duffel": "ContainerBagDuffel",
        "MarketSenseFixture.Wallpaper": "MaterialConstruction",
        "MarketSenseFixture.ConcretePowder": "MaterialConstruction",
        "MarketSenseFixture.ClayBrick": "MaterialConstruction",
        "MarketSenseFixture.PotteryClayPot": "MaterialPottery",
        "MarketSenseFixture.MetalOre": "MaterialMetalworking",
        "MarketSenseFixture.HardwareNails": "MaterialHardware",
        "MarketSenseFixture.TailoringRope": "MaterialTailoring",
        "MarketSenseFixture.FirewoodBundle": "MaterialFireSource",
        "MarketSenseFixture.GlassPanel": "MaterialGlass",
        "MarketSenseFixture.StoneMaterial": "MaterialStone",
        "MarketSenseFixture.Gunpowder": "MaterialChemical",
        "MarketSenseFixture.PackFrame": "MaterialCarpentry",
        "MarketSenseFixture.WoodMaterial": "MaterialWood",
        "MarketSenseFixture.UnknownBundle": "MaterialBundled",
        "MarketSenseFixture.GenericMaterial": "Material",
        "MarketSenseFixture.ToiletPaper": "MaterialPaper",
        "MarketSenseFixture.NoveltySkullGlasses": "Memento",
        "MarketSenseFixture.AnimalHead": "MaterialButchering",
        "MarketSenseFixture.LooseBag": "Container",
        "MarketSenseFixture.Television": "ElectronicsTelevision",
        "MarketSenseFixture.Radio": "ElectronicsRadio",
        "MarketSenseFixture.SleepingBag": "BuildingSurvivalSleepingBag",
        "MarketSenseFixture.Mattress": "BuildingFurnitureBed",
        "MarketSenseFixture.GymnMat": "BuildingFurnitureBed",
        "MarketSenseFixture.Tent": "BuildingSurvivalTent",
        "MarketSenseFixture.MoveableLamp": "BuildingFixtureLighting",
        "MarketSenseFixture.InstalledLamp": "BuildingFixtureLighting",
        "MarketSenseFixture.Flashlight": "ElectronicsFlashlight",
        "MarketSenseFixture.GunLight": "WeaponPart",
        "MarketSenseFixture.MoveableTannedHide": "MaterialTailoring",
        "MarketSenseFixture.MoveableBrokenGlass": "Junk",
        "MarketSenseFixture.MoveableSink": "BuildingFixturePlumbing",
        "MarketSenseFixture.SkillBook": "SkillBook",
        "MarketSenseFixture.CartographyMap": "LiteratureMap",
        "MarketSenseFixture.WeaponPart": "WeaponPart",
        "MarketSenseFixture.WaterContainer": "ContainerLiquid",
        "MarketSenseFixture.ProtectiveGorget": "ProtectiveGearNeck",
        "MarketSenseFixture.ComboWasherDryer": "ElectronicsLaundry",
        "MarketSenseFixture.LaundryBin": "BuildingFurnitureLaundry",
        "MarketSenseFixture.LightRoundTable": "BuildingFurnitureTable",
        "MarketSenseFixture.Counter": "BuildingFurnitureCounter",
        "MarketSenseFixture.Drawers": "BuildingFurnitureStorage",
        "MarketSenseFixture.MilitaryCrate": "BuildingFurnitureStorage",
        "MarketSenseFixture.Dishwasher": "ElectronicsAppliance",
        "MarketSenseFixture.GardenSeed": "GardeningSeed",
        "MarketSenseFixture.Compost": "GardeningCompost",
        "MarketSenseFixture.Fertilizer": "GardeningFertilizer",
        "MarketSenseFixture.SlugRepellent": "GardeningPestControl",
        "MarketSenseFixture.FitnessContraption": "BuildingRecreationFitness",
        "MarketSenseFixture.KickDrum": "BuildingRecreationDrum",
        "MarketSenseFixture.WallClock": "ElectronicsClock",
        "MarketSenseFixture.Gurney": "BuildingMedicalGurney",
        "MarketSenseFixture.ConcreteMixer": "BuildingCraftingMasonry",
    }
    check(
        "audited root and leaf heuristics",
        all(by_type.get(item, {}).get("primary") == primary
            for item, primary in expected_primary.items()),
        ", ".join(
            f"{item.rsplit('.', 1)[-1]}={by_type.get(item, {}).get('primary', '?')}"
            for item in sorted(expected_primary)
        ),
    )
    expected_paths = {
        "MarketSenseFixture.Bag": "Container > Bag > Bag",
        "MarketSenseFixture.Spear": "Weapon > Melee > Spear",
        "MarketSenseFixture.SpearTagFallback": "Weapon > Melee > Spear",
        "MarketSenseFixture.Backpack": "Container > Bag > Backpack",
        "MarketSenseFixture.Satchel": "Container > Bag > Satchel",
        "MarketSenseFixture.FannyPackFront": "Container > Bag > Fanny",
        "MarketSenseFixture.FannyPackBack": "Container > Bag > Fanny",
        "MarketSenseFixture.Bandolier": "Container > Bag > Bandolier",
        "MarketSenseFixture.Duffel": "Container > Bag > Duffel",
        "MarketSenseFixture.Wallpaper": "Resource > Material > Construction",
        "MarketSenseFixture.ConcretePowder": "Resource > Material > Construction",
        "MarketSenseFixture.ClayBrick": "Resource > Material > Construction",
        "MarketSenseFixture.PotteryClayPot": "Resource > Material > Pottery",
        "MarketSenseFixture.MetalOre": "Resource > Material > Metalworking",
        "MarketSenseFixture.HardwareNails": "Resource > Material > Hardware",
        "MarketSenseFixture.TailoringRope": "Resource > Material > Tailoring",
        "MarketSenseFixture.FirewoodBundle": "Resource > Material > FireSource",
        "MarketSenseFixture.GlassPanel": "Resource > Material > Glass",
        "MarketSenseFixture.StoneMaterial": "Resource > Material > Stone",
        "MarketSenseFixture.Gunpowder": "Resource > Material > Chemical",
        "MarketSenseFixture.PackFrame": "Resource > Material > Carpentry",
        "MarketSenseFixture.WoodMaterial": "Resource > Material > Wood",
        "MarketSenseFixture.UnknownBundle": "Resource > Material > Bundled",
        "MarketSenseFixture.GenericMaterial": "Resource > Material > Material",
        "MarketSenseFixture.ToiletPaper": "Resource > Material > Paper",
        "MarketSenseFixture.NoveltySkullGlasses": "Misc > Memento > Memento",
        "MarketSenseFixture.AnimalHead": "Resource > Material > Butchering",
        "MarketSenseFixture.LooseBag": "Container > General > General",
        "MarketSenseFixture.SleepingBag": "Building > Survival > SleepingBag",
        "MarketSenseFixture.Tent": "Building > Survival > Tent",
        "MarketSenseFixture.MoveableLamp": "Building > Fixture > Lighting",
        "MarketSenseFixture.Flashlight": "Electronics > Light > Flashlight",
        "MarketSenseFixture.MoveableTannedHide": "Resource > Material > Tailoring",
        "MarketSenseFixture.ComboWasherDryer": "Electronics > Appliance > Laundry",
        "MarketSenseFixture.LaundryBin": "Building > Furniture > Laundry",
        "MarketSenseFixture.LightRoundTable": "Building > Furniture > Table",
        "MarketSenseFixture.Counter": "Building > Furniture > Counter",
        "MarketSenseFixture.Drawers": "Building > Furniture > Storage",
        "MarketSenseFixture.MilitaryCrate": "Building > Furniture > Storage",
        "MarketSenseFixture.Dishwasher": "Electronics > Appliance > Appliance",
        "MarketSenseFixture.GardenSeed": "Building > Gardening > Seed",
        "MarketSenseFixture.Compost": "Building > Gardening > Compost",
        "MarketSenseFixture.Fertilizer": "Building > Gardening > Fertilizer",
        "MarketSenseFixture.SlugRepellent": "Building > Gardening > PestControl",
        "MarketSenseFixture.FitnessContraption": "Building > Recreation > Fitness",
        "MarketSenseFixture.KickDrum": "Building > Recreation > Drum",
        "MarketSenseFixture.WallClock": "Electronics > Appliance > Clock",
        "MarketSenseFixture.Gurney": "Building > Medical > Gurney",
        "MarketSenseFixture.ConcreteMixer": "Building > Crafting > Masonry",
    }
    check(
        "audited nested hierarchy paths",
        all(by_type.get(item, {}).get("categoryPath") == path
            for item, path in expected_paths.items()),
        ", ".join(
            f"{item.rsplit('.', 1)[-1]}={by_type.get(item, {}).get('categoryPath', '?')}"
            for item in sorted(expected_paths)
        ),
    )

    def classifier_source(item: str) -> str:
        detection = by_type.get(item, {}).get("detection") or {}
        classifier = detection.get("classifier") or {}
        details = classifier.get("details") or {}
        return str(details.get("source") or "")

    spear = by_type.get("MarketSenseFixture.Spear", {})
    spear_fallback = by_type.get("MarketSenseFixture.SpearTagFallback", {})
    check(
        "melee spear evidence is authoritative before fallbacks",
        (
            spear.get("primary") == "WeaponSpear"
            and classifier_source("MarketSenseFixture.Spear") == "weapon_melee"
            and (spear.get("context") or {}).get("weaponCategories")
            == ["base:improvised", "base:spear"]
            and spear_fallback.get("primary") == "WeaponSpear"
            and classifier_source("MarketSenseFixture.SpearTagFallback")
            == "weapon_melee_spear_tag"
        ),
        f"category={spear.get('primary', '?')} source={classifier_source('MarketSenseFixture.Spear')} "
        f"fallback={spear_fallback.get('primary', '?')} source="
        f"{classifier_source('MarketSenseFixture.SpearTagFallback')}",
    )

    wallpaper = by_type.get("MarketSenseFixture.Wallpaper", {})
    paper = by_type.get("MarketSenseFixture.ToiletPaper", {})
    paper_detection = paper.get("detection") or {}
    paper_details = ((paper_detection.get("final") or {}).get("details") or {})
    check(
        "resource labels retain evidence provenance",
        (
            classifier_source("MarketSenseFixture.Wallpaper") == "material_construction_evidence"
            and classifier_source("MarketSenseFixture.MetalOre") == "material_metalworking_evidence"
            and classifier_source("MarketSenseFixture.HardwareNails") == "material_hardware_evidence"
            and classifier_source("MarketSenseFixture.GlassPanel") == "material_glass_evidence"
            and paper_details.get("labelCorrectionReason") == "label_paper_goods"
            and wallpaper.get("categoryPath") == "Resource > Material > Construction"
        ),
        f"wallpaper={classifier_source('MarketSenseFixture.Wallpaper')} "
        f"metal={classifier_source('MarketSenseFixture.MetalOre')} "
        f"paper={paper_details.get('labelCorrectionReason', '?')}",
    )
    skull_glasses = by_type.get("MarketSenseFixture.NoveltySkullGlasses", {})
    check(
        "animal text does not reroute wearable mementos",
        skull_glasses.get("primary") == "Memento"
        and skull_glasses.get("category") == "Misc",
        f"category={skull_glasses.get('category', '?')} primary={skull_glasses.get('primary', '?')}",
    )

    bag_signal_checks = {
        "MarketSenseFixture.Backpack": "container_bag_body_back",
        "MarketSenseFixture.Satchel": "container_bag_body_satchel",
        "MarketSenseFixture.FannyPackFront": "container_bag_body_fanny",
        "MarketSenseFixture.FannyPackBack": "container_bag_body_fanny",
        "MarketSenseFixture.Bandolier": "container_bag_body_webbing",
        "MarketSenseFixture.Duffel": "container_bag_duffel_evidence",
    }
    bag_signal_ok = all(
        classifier_source(item) == source
        and "ContainerBag" in (by_type.get(item, {}).get("expandedTags") or [])
        and "Container" in (by_type.get(item, {}).get("expandedTags") or [])
        for item, source in bag_signal_checks.items()
    )
    check(
        "bag tags retain game evidence and parents",
        bag_signal_ok,
        ", ".join(
            f"{item.rsplit('.', 1)[-1]}={classifier_source(item)}"
            for item in sorted(bag_signal_checks)
        ),
    )

    combo = by_type.get("MarketSenseFixture.ComboWasherDryer", {})
    combo_context = combo.get("context") or {}
    combo_world = combo_context.get("worldObjectEvidence") or {}
    combo_caps = combo_context.get("capabilities") or {}
    check(
        "world-object capability evidence is exposed",
        (
            combo.get("primary") == "ElectronicsLaundry"
            and combo_world.get("objectClass") == "IsoCombinationWasherDryer"
            and combo_world.get("properties", {}).get("Material3") == "Electric"
            and "wash_clothing" in (combo_caps.get("capabilities") or [])
            and "dry_clothing" in (combo_caps.get("capabilities") or [])
            and "electricity" in (combo_caps.get("requirements") or [])
            and "water_supply" in (combo_caps.get("requirements") or [])
        ),
        f"primary={combo.get('primary', '?')} capabilities={combo_caps.get('capabilities', '?')} "
        f"requirements={combo_caps.get('requirements', '?')}",
    )
    table = by_type.get("MarketSenseFixture.LightRoundTable", {})
    table_context = table.get("context") or {}
    table_caps = table_context.get("capabilities") or {}
    fitness = by_type.get("MarketSenseFixture.FitnessContraption", {})
    fitness_caps = (fitness.get("context") or {}).get("capabilities") or {}
    check(
        "world semantics beat ambiguous names",
        (
            table.get("primary") == "BuildingFurnitureTable"
            and "table_surface" in (table_caps.get("capabilities") or [])
            and fitness.get("primary") == "BuildingRecreationFitness"
            and "exercise" in (fitness_caps.get("capabilities") or [])
        ),
        f"table={table.get('primary', '?')} fitness={fitness.get('primary', '?')}",
    )
    furniture_semantics = {
        item: (by_type.get(item, {}).get("context") or {}).get("capabilities") or {}
        for item in (
            "MarketSenseFixture.Counter", "MarketSenseFixture.Drawers",
            "MarketSenseFixture.MilitaryCrate", "MarketSenseFixture.Dishwasher",
        )
    }
    check(
        "table placement flags do not erase furniture semantics",
        (
            by_type.get("MarketSenseFixture.Counter", {}).get("primary") == "BuildingFurnitureCounter"
            and by_type.get("MarketSenseFixture.Drawers", {}).get("primary") == "BuildingFurnitureStorage"
            and by_type.get("MarketSenseFixture.MilitaryCrate", {}).get("primary") == "BuildingFurnitureStorage"
            and by_type.get("MarketSenseFixture.Dishwasher", {}).get("primary") == "ElectronicsAppliance"
            and "table_surface" not in (furniture_semantics["MarketSenseFixture.Counter"].get("capabilities") or [])
            and "table_surface" not in (furniture_semantics["MarketSenseFixture.Drawers"].get("capabilities") or [])
            and "table_surface" not in (furniture_semantics["MarketSenseFixture.MilitaryCrate"].get("capabilities") or [])
        ),
        ", ".join(
            f"{item.rsplit('.', 1)[-1]}={by_type.get(item, {}).get('primary', '?')}"
            for item in furniture_semantics
        ),
    )
    garden_expected = {
        "MarketSenseFixture.GardenSeed": "GardeningSeed",
        "MarketSenseFixture.Compost": "GardeningCompost",
        "MarketSenseFixture.Fertilizer": "GardeningFertilizer",
        "MarketSenseFixture.SlugRepellent": "GardeningPestControl",
    }
    check(
        "gardening subcategories use script tags and item use",
        all(by_type.get(item, {}).get("primary") == primary
            for item, primary in garden_expected.items()),
        ", ".join(
            f"{item.rsplit('.', 1)[-1]}={by_type.get(item, {}).get('primary', '?')}"
            for item in garden_expected
        ),
    )
    lamp_caps = (by_type.get("MarketSenseFixture.MoveableLamp", {}).get("context") or {}).get("capabilities") or {}
    sink_caps = (by_type.get("MarketSenseFixture.MoveableSink", {}).get("context") or {}).get("capabilities") or {}
    check(
        "placement surface is not a false table positive",
        (
            "table_surface" not in (lamp_caps.get("capabilities") or [])
            and "table_surface" not in (sink_caps.get("capabilities") or [])
            and by_type.get("MarketSenseFixture.MoveableLamp", {}).get("primary") == "BuildingFixtureLighting"
            and by_type.get("MarketSenseFixture.MoveableSink", {}).get("primary") == "BuildingFixturePlumbing"
        ),
        f"lamp={lamp_caps.get('capabilities', '?')} sink={sink_caps.get('capabilities', '?')}",
    )

    availability = {
        item: by_type.get(item, {}).get("availability") or {}
        for item in expected_types
    }
    check(
        "Lua runtime availability gate",
        (
            availability["MarketSenseFixture.FoodLow"].get("status") == "obtainable"
            and availability["MarketSenseFixture.CannedMeal"].get("status") == "obtainable"
            and availability["MarketSenseFixture.Bandage"].get("status") == "obtainable"
            and availability["MarketSenseFixture.DebugDummy"].get("status") == "excluded"
            and availability["MarketSenseFixture.DebugDummy"].get("obtainable") is False
        ),
        ", ".join(
            f"{item.rsplit('.', 1)[-1]}={availability[item].get('status', '?')}"
            for item in sorted(expected_types)
        ),
    )

    low = by_type.get("MarketSenseFixture.FoodLow", {})
    high = by_type.get("MarketSenseFixture.FoodHigh", {})
    check(
        "price responds to food stats",
        high.get("price", 0) > low.get("price", 0),
        f"FoodLow={low.get('price', '?')} FoodHigh={high.get('price', '?')}",
    )
    check(
        "description reaches context",
        low.get("description") == "a small portion of meat",
        f"description={low.get('description', '?')!r}",
    )
    canned = by_type.get("MarketSenseFixture.CannedMeal", {})
    check(
        "description affects subtype",
        canned.get("primary") == "FoodNonPerishableCanned",
        f"CannedMeal primary={canned.get('primary', '?')}",
    )
    canned_hierarchy = canned.get("hierarchy") or {}
    canned_detection = canned.get("detection") or {}
    check(
        "Lua hierarchy and detector provenance",
        (
            canned.get("categoryPath") == "Food > NonPerishable > Canned"
            and canned_hierarchy.get("subcategory") == "NonPerishable"
            and canned_hierarchy.get("leaf") == "Canned"
            and (canned_detection.get("classifier") or {}).get("signature") == "Food"
            and (canned_detection.get("final") or {}).get("primary") == "FoodNonPerishableCanned"
            and canned.get("evaluator", {}).get("api") == "DynamicTrading.GetPriceDetails"
        ),
        f"path={canned.get('categoryPath', '?')}, detector={(canned_detection.get('classifier') or {}).get('signature', '?')}",
    )
    check(
        "runtime variables and price audit",
        (
            canned.get("context", {}).get("calories") == 250
            and canned.get("context", {}).get("hunger") == 0.2
            and isinstance(canned.get("priceAudit"), list)
            and any(entry.get("label") == "raw score" for entry in canned.get("priceAudit") or [])
        ),
        f"calories={canned.get('context', {}).get('calories', '?')}, audit_steps={len(canned.get('priceAudit') or [])}",
    )
    check(
        "cache-stage comparison fields",
        (
            isinstance(canned.get("basePrice"), (int, float))
            and isinstance(canned.get("baseStock"), dict)
            and canned.get("baseStock", {}).get("max", 0) > 0
        ),
        f"basePrice={canned.get('basePrice', '?')}, baseStock={canned.get('baseStock', '?')}",
    )
    check(
        "numeric method bridge",
        (
            abs(float(low.get("hunger", 0)) - 0.05) < 1e-9
            and abs(float(by_type.get("MarketSenseFixture.Axe", {}).get("maxDamage", 0)) - 2) < 1e-9
            and abs(float(by_type.get("MarketSenseFixture.Bag", {}).get("capacity", 0)) - 20) < 1e-9
        ),
        "hunger, weapon damage, and container capacity",
    )
    overridden = run_lua_result(
        lua, mock_definitions(), {"PriceGlobalValue": 100}
    )
    overridden_by_type = {row.get("fullType"): row for row in overridden.rows}
    check(
        "sandbox override reaches Lua pricing",
        (
            overridden.metadata.get("requested", {}).get("PriceGlobalValue") == 100
            and overridden.metadata.get("runtime", {}).get("pricing", {}).get("globalValue") == 100
            and overridden_by_type.get("MarketSenseFixture.CannedMeal", {}).get("price", 0)
            == canned.get("price", 0) + 100
        ),
        f"base={canned.get('price', '?')} overridden="
        f"{overridden_by_type.get('MarketSenseFixture.CannedMeal', {}).get('price', '?')}",
    )
    return all(check["passed"] for check in checks), checks


def print_self_test(checks: list[dict[str, Any]]) -> None:
    print("MarketSense offline harness self-test")
    for check in checks:
        status = "PASS" if check["passed"] else "FAIL"
        print(f"  {status:<4} {check['name']}: {check['detail']}")
    passed = sum(1 for check in checks if check["passed"])
    print(f"Result: {'PASS' if passed == len(checks) else 'FAIL'} ({passed}/{len(checks)} checks)")
