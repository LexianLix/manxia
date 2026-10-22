import io
import unittest

from PIL import Image, ImageDraw
from android_surface import home_title_evidence


class PaintedHomeTest(unittest.TestCase):
    xml = '<hierarchy><node package="io.manxia.manxia" content-desc="我的书架" bounds="[10,10][190,60]"/></hierarchy>'

    def screenshot(self, painted):
        image = Image.new("RGB", (200, 120), "#f7f7f2")
        if painted:
            ImageDraw.Draw(image).text((12, 20), "MY LIBRARY", fill="#171d19", font_size=24)
        output = io.BytesIO()
        image.save(output, format="PNG")
        return output.getvalue()

    def test_semantics_without_painted_title_is_rejected(self):
        self.assertFalse(home_title_evidence(self.xml, self.screenshot(False))["painted"])

    def test_painted_title_is_accepted(self):
        self.assertTrue(home_title_evidence(self.xml, self.screenshot(True))["painted"])

    def test_missing_or_outside_title_is_rejected(self):
        image = self.screenshot(True)
        self.assertFalse(home_title_evidence("<hierarchy/>", image)["painted"])
        self.assertFalse(home_title_evidence(self.xml.replace("190,60", "900,60"), image)["painted"])


if __name__ == "__main__":
    unittest.main()
