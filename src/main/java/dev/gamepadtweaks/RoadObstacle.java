package dev.gamepadtweaks;

import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.sprite.IsoSprite;
import zombie.iso.sprite.IsoSpriteInstance;

/** The low street props that are rendered on the road but exert no force on a wheel. */
final class RoadObstacle {
    private static final int X_NEAR = 1, Y_NEAR = 2, X_FAR = 4, Y_FAR = 8;
    private static final int DIAGONAL_XY = 16, DIAGONAL_YX = 32, COMPLEX = 64;
    private static final int PARK_X_NEAR = 128, PARK_Y_NEAR = 256, PARK_X_FAR = 512, PARK_Y_FAR = 1024;
    private static final int CORNER_NEAR = 2048, CORNER_FAR = 4096;
    static final int CURB = 1, PARKING_STOP = 2;

    private RoadObstacle() {}

    static int shapes(IsoGridSquare square) {
        if (square == null) {
            return 0;
        }
        int shapes = 0;
        for (int i = 0; i < square.getObjects().size(); i++) {
            IsoObject object = square.getObjects().get(i);
            if (object == null) {
                continue;
            }
            shapes |= shape(object.getSprite());
            for (int j = 0; j < object.getAttachedAnimSpriteCount(); j++) {
                IsoSpriteInstance attached = object.getAttachedAnimSprite().get(j);
                shapes |= shape(attached.getParentSprite());
            }
        }
        return shapes;
    }

    private static int shape(IsoSprite sprite) {
        if (sprite == null || sprite.tilesetName == null) {
            return 0;
        }
        int index = sprite.tileSheetIndex;
        if (sprite.tilesetName.equals("street_decoration_01")) {
            return switch (index) {
                case 32, 33, 34 -> PARK_Y_NEAR;
                case 35, 36, 37 -> PARK_X_NEAR;
                case 40, 41, 42 -> PARK_Y_FAR;
                case 43, 44, 45 -> PARK_X_FAR;
                default -> 0;
            };
        }
        if (sprite.tilesetName.equals("street_curbs_01")) {
            return switch (index) {
                case 0, 2 -> X_FAR | Y_FAR;
                case 4, 6, 9, 11, 13, 15, 16, 19, 21, 25, 27, 34, 35, 43 -> X_FAR;
                case 5, 7, 8, 10, 12, 14, 17, 18, 20, 24, 26, 32, 33, 42 -> Y_FAR;
                case 36, 37, 40 -> X_NEAR;
                case 38, 39, 41 -> Y_NEAR;
                case 44 -> X_NEAR | Y_NEAR;
                case 45 -> X_NEAR | Y_FAR;
                case 46 -> X_FAR | Y_NEAR;
                case 22, 23, 48, 49, 50, 51 -> DIAGONAL_XY;
                case 52, 53, 54, 56, 57 -> DIAGONAL_YX;
                case 59 -> CORNER_NEAR;
                case 1, 3, 60, 61, 62 -> CORNER_FAR;
                default -> 0;
            };
        }
        // The diagonal corner pieces have irregular footprints. Detect entry on their tile.
        return sprite.tilesetName.equals("street_curbs_01_diag") || sprite.tilesetName.equals("street_curbs_01_diag_2")
                ? COMPLEX : 0;
    }

    static int contact(int shapes, float x, float y) {
        if ((shapes & PARK_X_NEAR) != 0 && Math.abs(x - 0.31f) < 0.13f
                || (shapes & PARK_Y_NEAR) != 0 && Math.abs(y - 0.35f) < 0.13f
                || (shapes & PARK_X_FAR) != 0 && Math.abs(x - 0.76f) < 0.13f
                || (shapes & PARK_Y_FAR) != 0 && Math.abs(y - 0.79f) < 0.13f) {
            return PARKING_STOP;
        }
        if ((shapes & X_NEAR) != 0 && x < 0.22f || (shapes & Y_NEAR) != 0 && y < 0.22f
                || (shapes & X_FAR) != 0 && x > 0.73f || (shapes & Y_FAR) != 0 && y > 0.73f
                || (shapes & DIAGONAL_XY) != 0 && Math.abs(x - y) < 0.23f
                || (shapes & DIAGONAL_YX) != 0 && Math.abs(x + y - 1) < 0.23f
                || (shapes & CORNER_NEAR) != 0 && x + y < 0.42f
                || (shapes & CORNER_FAR) != 0 && x + y > 1.54f
                || (shapes & COMPLEX) != 0) {
            return CURB;
        }
        return 0;
    }
}
