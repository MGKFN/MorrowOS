/* MorrowOS "Dawn" — Calamares slideshow
 *
 * Deliberately minimal. The frames are pre-rendered PNGs with their text
 * already baked in, so there is no QML-drawn text, no fonts to resolve and
 * no layout to get wrong on an unexpected window size.
 *
 * If this file fails to load, Calamares logs the error and shows an empty
 * slideshow area -- the install itself still proceeds. That is the intended
 * failure mode; do not add anything here that the install depends on.
 */
import QtQuick 2.5
import calamares.slideshow 1.0

Presentation {
    id: presentation

    Timer {
        interval: 9000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        Image {
            source: "slide-1.png"
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
            horizontalAlignment: Image.AlignHCenter
            verticalAlignment: Image.AlignVCenter
        }
    }
    Slide {
        Image {
            source: "slide-2.png"
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
            horizontalAlignment: Image.AlignHCenter
            verticalAlignment: Image.AlignVCenter
        }
    }
    Slide {
        Image {
            source: "slide-3.png"
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
            horizontalAlignment: Image.AlignHCenter
            verticalAlignment: Image.AlignVCenter
        }
    }
    Slide {
        Image {
            source: "slide-4.png"
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
            horizontalAlignment: Image.AlignHCenter
            verticalAlignment: Image.AlignVCenter
        }
    }
}
