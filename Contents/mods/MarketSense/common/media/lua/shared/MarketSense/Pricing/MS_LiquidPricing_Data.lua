-- MarketSense base liquid prices.
--
-- These are prices for the fluid content per litre, not for the vessel that
-- happens to contain it.  Workshop mods can register more precise values at
-- runtime through MarketSense.FluidPricing.register().

return {
    version = 1,
    defaultPricePerLiter = 5.0,

    -- Exact PZ fluid types.  The key is deliberately the fluid name (Water,
    -- Petrol, Cola, ...), never an item/container name.
    liquids = {
        Water = { pricePerLiter = 5.0, primary = "LiquidWater" },
        TaintedWater = { pricePerLiter = 1.0, primary = "LiquidTaintedWater" },
        CarbonatedWater = { pricePerLiter = 5.0, primary = "LiquidCarbonatedWater" },

        Cola = { pricePerLiter = 6.0, primary = "LiquidSoda" },
        ColaDiet = { pricePerLiter = 6.0, primary = "LiquidSoda" },
        GingerAle = { pricePerLiter = 6.0, primary = "LiquidSoda" },
        SodaBlueberry = { pricePerLiter = 7.0, primary = "LiquidSoda" },

        JuiceApple = { pricePerLiter = 7.0, primary = "LiquidJuice" },
        JuiceCranberry = { pricePerLiter = 7.0, primary = "LiquidJuice" },
        JuiceFruitpunch = { pricePerLiter = 7.0, primary = "LiquidJuice" },
        JuiceGrape = { pricePerLiter = 7.0, primary = "LiquidJuice" },
        JuiceLemon = { pricePerLiter = 7.0, primary = "LiquidJuice" },
        JuiceOrange = { pricePerLiter = 7.0, primary = "LiquidJuice" },
        JuiceTomato = { pricePerLiter = 6.0, primary = "LiquidJuice" },

        CowMilk = { pricePerLiter = 6.0, primary = "LiquidMilk" },
        MilkChocolate = { pricePerLiter = 7.0, primary = "LiquidMilk" },
        Coffee = { pricePerLiter = 7.0, primary = "LiquidCoffee" },
        Tea = { pricePerLiter = 7.0, primary = "LiquidTea" },

        Beer = { pricePerLiter = 8.0, primary = "LiquidBeer" },
        Wine = { pricePerLiter = 15.0, primary = "LiquidWine" },
        Brandy = { pricePerLiter = 18.0, primary = "LiquidAlcohol" },
        Champagne = { pricePerLiter = 22.0, primary = "LiquidAlcohol" },
        Cider = { pricePerLiter = 10.0, primary = "LiquidAlcohol" },
        CoffeeLiqueur = { pricePerLiter = 18.0, primary = "LiquidAlcohol" },
        Curacao = { pricePerLiter = 18.0, primary = "LiquidAlcohol" },
        Gin = { pricePerLiter = 18.0, primary = "LiquidAlcohol" },
        Rum = { pricePerLiter = 18.0, primary = "LiquidAlcohol" },
        Scotch = { pricePerLiter = 22.0, primary = "LiquidAlcohol" },
        Sherry = { pricePerLiter = 16.0, primary = "LiquidAlcohol" },
        Tequila = { pricePerLiter = 18.0, primary = "LiquidAlcohol" },
        Vermouth = { pricePerLiter = 16.0, primary = "LiquidAlcohol" },
        Vodka = { pricePerLiter = 18.0, primary = "LiquidAlcohol" },
        Whiskey = { pricePerLiter = 22.0, primary = "LiquidAlcohol" },

        Grenadine = { pricePerLiter = 10.0, primary = "LiquidSyrup" },
        SimpleSyrup = { pricePerLiter = 8.0, primary = "LiquidSyrup" },

        Blood = { pricePerLiter = 2.0, primary = "LiquidBlood" },
        AnimalBlood = { pricePerLiter = 2.0, primary = "LiquidAnimalBlood" },
        AnimalGrease = { pricePerLiter = 4.0, primary = "LiquidAnimalGrease" },
        Petrol = { pricePerLiter = 8.0, primary = "LiquidFuel" },
        Dye = { pricePerLiter = 8.0, primary = "LiquidDye" },
        HairDye = { pricePerLiter = 10.0, primary = "LiquidHairDye" },
        RubbingAlcohol = { pricePerLiter = 12.0, primary = "LiquidMedical" },
        Bleach = { pricePerLiter = 5.0, primary = "LiquidChemical" },
        CleaningLiquid = { pricePerLiter = 5.0, primary = "LiquidChemical" },
        Cologne = { pricePerLiter = 6.0, primary = "LiquidChemical" },
        Perfume = { pricePerLiter = 8.0, primary = "LiquidChemical" },
    },

    -- Family defaults keep new Workshop fluid names useful without silently
    -- pretending that the exact fluid has a known market anchor.
    primaryDefaults = {
        LiquidWater = 5.0,
        LiquidTaintedWater = 1.0,
        LiquidCarbonatedWater = 5.0,
        LiquidSoda = 6.0,
        LiquidJuice = 7.0,
        LiquidSyrup = 8.0,
        LiquidMilk = 6.0,
        LiquidCoffee = 7.0,
        LiquidTea = 7.0,
        LiquidAlcohol = 18.0,
        LiquidBeer = 8.0,
        LiquidWine = 15.0,
        LiquidBlood = 2.0,
        LiquidAnimalBlood = 2.0,
        LiquidAnimalGrease = 4.0,
        LiquidFuel = 8.0,
        LiquidDye = 8.0,
        LiquidHairDye = 10.0,
        LiquidChemical = 5.0,
        LiquidMedical = 12.0,
        LiquidIndustrial = 5.0,
        LiquidUnknown = 5.0,
    },
}
