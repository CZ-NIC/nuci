#include <QApplication>
#include <QFile>
#include <QDomDocument>

int main(int argc, char *argv[]) {
	QApplication app(argc, argv);
	QFile f;
	f.open(stdin, QIODevice::ReadOnly);
	QDomDocument doc;
	doc.setContent(&f, true);
	printf("%s", doc.toString().toLocal8Bit().data());
}
