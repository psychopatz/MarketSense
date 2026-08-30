"""Deterministic item and recipe fixtures for the offline harness.

This package is intentionally isolated from the production scan pipeline. It is
loaded only by the explicit self-test command or GUI action.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from marketsense_app.models import ItemDefinition, WorkshopMod

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
            "hungerChange": -5, "calories": 50, "daysFresh": 1, "daysRotten": 2,
            "actualWeight": 0.2, "description": "a small portion of meat",
            "canSpawnAsLoot": True,
        }),
        make("FoodHigh", {
            "itemType": "Food", "displayCategory": "Food", "foodType": "Meat",
            "hungerChange": -80, "calories": 800, "daysFresh": 10, "daysRotten": 20,
            "actualWeight": 0.2, "description": "a large portion of meat",
            "canSpawnAsLoot": True,
        }),
        make("FoodUnit", {
            "itemType": "Food", "displayCategory": "Food", "foodType": "Meat",
            "hungerChange": -10, "calories": 100, "daysFresh": 5, "daysRotten": 10,
            "actualWeight": 0.2, "description": "a single unpacked food unit",
            "canSpawnAsLoot": True,
        }),
        make("FoodCarton", {
            "itemType": "Food", "displayCategory": "Food", "cantEat": True,
            "doubleClickRecipe": "OpenFoodCarton",
            "description": "a carton containing several food units",
            "canSpawnAsLoot": True,
        }),
        make("CannedMeal", {
            "itemType": "Food", "displayCategory": "Food", "hungerChange": -20,
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
        # These fixtures intentionally use the same namespaced tag form as
        # vanilla 42.20 (for example Base:Smokable). They guard the category
        # gates that previously compared only the short token.
        make("NamespacedFirearm", {
            "itemType": "base:weapon", "displayCategory": "Weapon",
            "tags": ["base:firearm"], "ammoType": "base:bullets_9mm",
            "minDamage": 0.6, "maxDamage": 1.0, "maxRange": 15,
            "maxHitCount": 1, "conditionMax": 10, "actualWeight": 1.5,
            "description": "a compact handgun", "canSpawnAsLoot": True,
        }),
        make("NamespacedMemento", {
            "itemType": "base:normal", "displayCategory": "General",
            "tags": ["base:ismemento"], "description": "a keepsake",
            "canSpawnAsLoot": True,
        }),
        make("NamespacedSmoking", {
            "itemType": "base:normal", "displayCategory": "Tool",
            "tags": ["base:smokable"], "description": "a tobacco pipe",
            "canSpawnAsLoot": True,
        }),
        make("WorkshopNamespacedSmoking", {
            "itemType": "base:normal", "displayCategory": "Tool",
            "tags": ["WorkshopTools:smokable"], "description": "a tobacco pipe",
            "canSpawnAsLoot": True,
        }),
        make("NamespacedCookingUtensil", {
            "itemType": "base:normal", "displayCategory": "Tool",
            "tags": ["base:spatula"], "description": "a kitchen utensil",
            "canSpawnAsLoot": True,
        }),
        make("NamespacedFood", {
            "itemType": "base:normal", "displayCategory": "General",
            "foodType": "Meat", "tags": ["base:meat"],
            "hungerChange": -25, "calories": 300, "daysFresh": 2,
            "daysRotten": 4, "actualWeight": 0.4,
            "description": "a portion of meat", "canSpawnAsLoot": True,
        }),
        make("NamespacedJewelry", {
            "itemType": "base:clothing", "displayCategory": "Clothing",
            "bodyLocation": "base:neck", "tags": ["base:diamondjewellery"],
            "description": "a diamond necklace", "canSpawnAsLoot": True,
        }),
        make("NamespacedAmmoContainer", {
            "itemType": "base:container", "displayCategory": "Bag",
            "bodyLocation": "base:back", "tags": ["base:ammocase"],
            "capacity": 10, "weightReduction": 20,
            "description": "a wearable ammunition case", "canSpawnAsLoot": True,
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
        make("ImprovisedClub", {
            "itemType": "base:weapon", "displayCategory": "WeaponCrafted",
            "weaponCategories": ["base:improvised"], "minDamage": 0.7,
            "maxDamage": 1.1, "maxRange": 1, "conditionMax": 5,
            "actualWeight": 1.4, "description": "a crude improvised club",
            "canSpawnAsLoot": True,
        }),
        make("Unarmed", {
            "itemType": "base:weapon", "displayCategory": "Weapon",
            "weaponCategories": ["base:unarmed"], "minDamage": 0,
            "maxDamage": 0, "maxRange": 1, "conditionMax": 0,
            "actualWeight": 0, "description": "unarmed combat",
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
        # The vessel is not the category: these rows exercise the primary
        # fluid path used by the live InventoryItem API.
        make("LiquidWater", {
            "itemType": "base:drainable", "displayCategory": "Water",
            "fluidContainer": True, "fluidContainerName": "Bottle",
            "fluidTypes": ["Water"], "fluidCapacity": 1.0, "fluidAmount": 1.0,
            "thirstChange": -0.25, "description": "a bottle of water",
            "canSpawnAsLoot": True,
        }),
        make("LiquidWaterTwoLiter", {
            "itemType": "base:drainable", "displayCategory": "Water",
            "fluidContainer": True, "fluidContainerName": "LargeBottle",
            "fluidTypes": ["Water"], "fluidCapacity": 2.0, "fluidAmount": 2.0,
            "thirstChange": -0.50, "actualWeight": 0.8,
            "description": "two litres of water",
            "canSpawnAsLoot": True,
        }),
        make("LiquidWaterInCan", {
            "itemType": "base:drainable", "displayCategory": "Water",
            "fluidContainer": True, "fluidContainerName": "MetalCan",
            "fluidTypes": ["Water"], "fluidCapacity": 2.0, "fluidAmount": 2.0,
            "thirstChange": -0.50, "actualWeight": 3.0,
            "description": "two litres of water in a can",
            "canSpawnAsLoot": True,
        }),
        make("LiquidSoda", {
            "itemType": "base:drainable", "displayCategory": "Food",
            "fluidContainer": True, "fluidContainerName": "PopBottle",
            "fluidTypes": ["Cola"], "fluidCapacity": 2.0, "fluidAmount": 2.0,
            "thirstChange": -0.20, "description": "a bottle of soda",
            "canSpawnAsLoot": True,
        }),
        make("LiquidBlood", {
            "itemType": "base:drainable", "displayCategory": "Medical",
            "fluidContainer": True, "fluidContainerName": "BloodBag",
            "fluidTypes": ["Blood"], "fluidCapacity": 0.5, "fluidAmount": 0.5,
            "description": "a blood bag", "canSpawnAsLoot": True,
        }),
        make("EmptyFluidBottle", {
            "itemType": "base:drainable", "displayCategory": "Water",
            "fluidContainer": True, "fluidContainerName": "Bottle",
            "fluidTypes": [], "fluidCapacity": 1.0,
            "description": "an empty bottle", "canSpawnAsLoot": True,
        }),
        make("ProtectiveGorget", {
            "itemType": "base:clothing", "displayCategory": "ProtectiveGear",
            "bodyLocation": "Gorget", "description": "a protective neck guard",
            "canSpawnAsLoot": True,
        }),
        # Subcategory fixtures: each one carries the same narrow engine or
        # script evidence used by the live scan, plus a material/weapon
        # collision and a root-precedence gardening tool regression.
        make("MaterialWeaponBar", {
            "itemType": "base:weapon", "displayCategory": "MaterialWeapon",
            "tags": ["base:hasmetal", "base:ironmaterial", "base:barstock"],
            "minDamage": 0.1, "maxDamage": 0.4, "canSpawnAsLoot": True,
            "description": "an iron bar used as metalworking stock",
        }),
        make("ImprovisedBowlingPin", {
            "itemType": "base:weapon", "displayCategory": "SportsWeapon",
            "tags": ["base:nomaintenancexp"],
            "weaponCategories": ["base:improvised", "base:smallblunt"],
            "minDamage": 0.4, "maxDamage": 0.9, "canSpawnAsLoot": True,
            "description": "a bowling pin used as an improvised weapon",
        }),
        make("ContainerCooler", {
            "itemType": "base:container", "displayCategory": "Container",
            "capacity": 12, "description": "a portable cooler", "canSpawnAsLoot": True,
        }),
        make("ContainerMedicalKit", {
            "itemType": "base:container", "displayCategory": "Container",
            "capacity": 2, "description": "a camping FirstAidKit", "canSpawnAsLoot": True,
        }),
        make("ContainerParcel", {
            "itemType": "base:container", "displayCategory": "Container",
            "capacity": 5, "description": "a small delivery parcel", "canSpawnAsLoot": True,
        }),
        make("ElectronicsRemote", {
            "itemType": "base:normal", "displayCategory": "Electronics",
            "description": "a television remote controller", "canSpawnAsLoot": True,
        }),
        make("ElectronicsAudio", {
            "itemType": "base:normal", "displayCategory": "Electronics",
            "description": "a portable speaker amplifier", "canSpawnAsLoot": True,
        }),
        make("ToolMeasure", {
            "itemType": "base:normal", "displayCategory": "Tool",
            "description": "a MeasuringTape for precise work", "canSpawnAsLoot": True,
        }),
        make("ToolAnvil", {
            "itemType": "base:normal", "displayCategory": "Tool",
            "description": "a small blacksmith bench anvil", "canSpawnAsLoot": True,
        }),
        make("GardeningSpray", {
            "itemType": "base:drainable", "displayCategory": "Gardening",
            "description": "a GardeningSprayAphids can", "canSpawnAsLoot": True,
        }),
        make("GardeningShovel", {
            "itemType": "base:weapon", "displayCategory": "Gardening",
            "tags": ["base:sharpenable", "base:digplow", "base:hasmetal"],
            "weaponCategories": ["base:smallblade"], "minDamage": 0.2,
            "maxDamage": 0.4, "canSpawnAsLoot": True,
            "description": "a hand shovel for digging soil",
        }),
        make("HollowBook", {
            "itemType": "base:container", "displayCategory": "Literature",
            "tags": ["base:hollowbook"], "capacity": 2,
            "description": "a hollow book", "canSpawnAsLoot": True,
        }),
        make("HollowBookHandgun", {
            "itemType": "base:container", "displayCategory": "Literature",
            "tags": ["base:hollowbook"], "capacity": 2,
            "description": "a hollow book for a handgun", "canSpawnAsLoot": True,
        }),
        make("MiscFishing", {
            "itemType": "base:normal", "displayCategory": "Fishing",
            "tags": ["base:fishinghook"], "description": "a fishing hook",
            "isFishingLure": True,
            "canSpawnAsLoot": True,
        }),
        make("MoveableShelf", {
            "itemType": "base:moveable", "displayCategory": "Furniture",
            "worldObjectSprite": "furniture_shelving_01_28",
            "description": "a moveable metal shelving unit", "canSpawnAsLoot": True,
        }),
        make("FoodMix", {
            "itemType": "base:food", "displayCategory": "Food",
            "isCraftRecipeProduct": True, "calories": 10, "hungerChange": -5,
            "description": "GravyMix ingredient", "canSpawnAsLoot": True,
        }),
        ItemDefinition(
            full_type="MarketSenseFixture.ModFoodRecipe", module="MarketSenseFixture",
            props={
                "itemType": "base:food", "displayCategory": "Food",
                "isCraftRecipeProduct": True, "calories": 10, "hungerChange": -5,
                "description": "a workshop recipe food product",
                "canSpawnAsLoot": True,
            }, mod=fixture_mod, script_path="<offline-fixture>",
        ),
        make("DebugDummy", {
            "displayCategory": "Hidden", "displayName": "DUMMY ITEM", "hidden": True,
            "canSpawnAsLoot": True,
        }),
    ]


def mock_yield_recipes() -> dict[str, list[dict[str, Any]]]:
    return {
        "MarketSenseFixture.FoodCarton": [{
            "recipe": "OpenFoodCarton",
            "source": "offline_recipe_graph",
            "sourceFullType": "MarketSenseFixture.FoodCarton",
            "inputAmount": 1.0,
            "inputCount": 1,
            "outputs": [{
                "fullType": "MarketSenseFixture.FoodUnit",
                "quantity": 4,
                "chance": 1.0,
                "inputFlags": [],
                "outputFlags": [],
                "inheritFoodAge": False,
            }],
            "resolution": "exact",
            "nameHeuristic": True,
            "candidateMethod": "explicit_property",
        }],
        "MarketSenseFixture.UnknownBundle": [{
            "recipe": "OpenResourceBundle",
            "source": "offline_recipe_graph",
            "sourceFullType": "MarketSenseFixture.UnknownBundle",
            "inputAmount": 1.0,
            "inputCount": 1,
            "outputs": [{
                "fullType": "MarketSenseFixture.WoodMaterial",
                "quantity": 3,
                "chance": 1.0,
                "inputFlags": [],
                "outputFlags": [],
                "inheritFoodAge": False,
            }],
            "resolution": "exact",
            "nameHeuristic": True,
            "candidateMethod": "explicit_property",
        }],
    }
