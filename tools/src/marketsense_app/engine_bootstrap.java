import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;

/**
 * Loads the real PZ script and Lua layers without starting a world.
 *
 * This file intentionally uses reflection: the installed PZ jar may be newer
 * than the system JDK, while the PZ-provided Java runtime can still execute
 * the resulting Java 17 bytecode.
 */
final class MarketSenseEngineBootstrap {
    private MarketSenseEngineBootstrap() {
    }

    private static Class<?> type(String name) throws ClassNotFoundException {
        return Class.forName(name);
    }

    private static Object staticField(String className, String fieldName) throws Exception {
        Field field = type(className).getField(fieldName);
        return field.get(null);
    }

    private static void setStaticBoolean(String className, String fieldName, boolean value)
        throws Exception {
        Field field = type(className).getField(fieldName);
        field.setBoolean(null, value);
    }

    private static Object invoke(Object target, String methodName, Object... arguments)
        throws Exception {
        Class<?> targetClass = target instanceof Class<?>
            ? (Class<?>) target
            : target.getClass();
        Method selected = null;
        for (Method method : targetClass.getMethods()) {
            if (!method.getName().equals(methodName)
                || method.getParameterCount() != arguments.length) {
                continue;
            }
            boolean compatible = true;
            Class<?>[] parameters = method.getParameterTypes();
            for (int index = 0; index < parameters.length; index++) {
                if (arguments[index] != null
                    && !box(parameters[index]).isInstance(arguments[index])) {
                    compatible = false;
                    break;
                }
            }
            if (compatible) {
                selected = method;
                break;
            }
        }
        if (selected == null) {
            throw new NoSuchMethodException(targetClass.getName() + "." + methodName);
        }
        return selected.invoke(target instanceof Class<?> ? null : target, arguments);
    }

    private static Class<?> box(Class<?> type) {
        if (!type.isPrimitive()) return type;
        if (type == boolean.class) return Boolean.class;
        if (type == byte.class) return Byte.class;
        if (type == short.class) return Short.class;
        if (type == int.class) return Integer.class;
        if (type == long.class) return Long.class;
        if (type == float.class) return Float.class;
        if (type == double.class) return Double.class;
        if (type == char.class) return Character.class;
        return type;
    }

    public static void main(String[] args) throws Exception {
        if (args.length < 3) {
            throw new IllegalArgumentException("cache root, harness path, and mod id are required");
        }

        System.setProperty("zomboid.steam", "0");
        Object fileSystem = staticField("zombie.ZomboidFileSystem", "instance");
        invoke(fileSystem, "setCacheDir", args[0]);
        invoke(fileSystem, "init");

        invoke(staticField("zombie.core.random.RandStandard", "INSTANCE"), "init");
        invoke(staticField("zombie.core.random.RandLua", "INSTANCE"), "init");
        setStaticBoolean("zombie.network.GameServer", "server", true);
        @SuppressWarnings("unchecked")
        ArrayList<String> mods = (ArrayList<String>) staticField(
            "zombie.network.GameServer", "ServerMods"
        );
        mods.clear();
        mods.add(args[2]);
        invoke(fileSystem, "loadMods", new ArrayList<String>(mods));

        Class<?> luaManager = type("zombie.Lua.LuaManager");
        invoke(luaManager, "init");
        Object scriptManager = staticField("zombie.scripting.ScriptManager", "instance");
        invoke(scriptManager, "Load");
        invoke(luaManager, "initChecksum");
        invoke(luaManager, "LoadDirBase", "shared");
        invoke(luaManager, "LoadDirBase", "server");
        invoke(luaManager, "finishChecksum");
        invoke(scriptManager, "LoadedAfterLua");

        // The generated harness is loaded by LoadDirBase("server"). RunLua is
        // retained as a fallback for unusual mod-loader layouts.
        invoke(luaManager, "RunLua", args[1]);
    }
}
