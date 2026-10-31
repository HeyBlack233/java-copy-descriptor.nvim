package lib;

import java.util.List;
import java.util.Map;

public class TinyDep {
    public class Nested {
        public Nested(int value) {
        }
    }

    public class DefaultNested {
    }

    public TinyDep(String value) {
    }

    public TinyDep(int value) {
    }

    public String format(List<String> values) {
        return "";
    }

    public static String describe(Map<String, Integer> values, int... counts) {
        return "";
    }

    public static int overloaded(int value) {
        return value;
    }

    public static int overloaded(String value) {
        return value.length();
    }

    public static <T extends Number> T pick(T value) {
        return value;
    }
}
