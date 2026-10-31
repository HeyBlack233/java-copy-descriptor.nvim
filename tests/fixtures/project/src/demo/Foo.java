package demo;

import java.util.List;
import java.util.Map;
import lib.TinyDep;

public class Foo {
    public interface Named {
        String name();
    }

    public static class Circle implements Named {
        public String name() {
            return "circle";
        }
    }

    public static class Outer {
        public class Inner {
            public Inner(int value) {
            }
        }

        public class DefaultInner {
        }
    }

    public enum Color {
        RED("red");

        private final String label;

        Color(String label) {
            this.label = label;
        }

        public String label() {
            return label;
        }
    }

    public record Point(int x, int y) {
        public Point {
        }
    }

    public static class Plain {
    }

    public static class Base {
        public Base(int value) {
        }
    }

    public static class Child extends Base {
        public Child() {
            super(1);
        }
    }

    public static class Chain {
        public Chain(int value) {
            this("x");
        }

        public Chain(String value) {
        }
    }

    public Foo() {
    }

    private static int hidden(int value) {
        return value + 1;
    }

    public static int sum(int... values) {
        int total = 0;
        for (int value : values) {
            total += value;
        }
        return total;
    }

    public static <T extends Number> T identity(T value) {
        return value;
    }

    public int[] array(String[] values) {
        return new int[0];
    }

    public int[][] matrix(String[][] values) {
        return new int[0][0];
    }

    public String plain(String text, Map<String, List<Long>> map) {
        return text;
    }

    public static void main(String[] args) {
        Foo foo = new Foo();
        hidden(1);
        sum(1, 2, 3);
        Integer id = identity(1);
        foo.array(new String[]{"a"});
        foo.plain("x", null);

        Named named = new Circle();
        named.name();

        Foo.Outer outer = new Foo.Outer();
        Foo.Outer.Inner inner = outer.new Inner(1);
        Foo.Outer.DefaultInner defaultInner = outer.new DefaultInner();

        Color color = Color.RED;
        color.label();

        Point point = new Point(1, 2);
        Plain plain = new Plain();
        Child child = new Child();
        Chain chain = new Chain(1);
        int[][] matrix = foo.matrix(new String[][]{{"a"}});

        TinyDep dep = new TinyDep("x");
        TinyDep dep2 = new TinyDep(1);
        TinyDep.Nested nestedDep = new TinyDep("x").new Nested(1);
        TinyDep.DefaultNested defaultNestedDep = new TinyDep("x").new DefaultNested();
        dep.format(null);
        TinyDep.describe(null, 1, 2);
        TinyDep.pick(1);
        TinyDep.overloaded(1);
        TinyDep.overloaded("x");
    }
}
