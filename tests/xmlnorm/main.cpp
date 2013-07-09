#include <QCoreApplication>
#include <QFile>
#include <QDomDocument>

int main(int argc, char *argv[]) {
	QCoreApplication app(argc, argv);
	QFile f;
	f.open(stdin, QIODevice::ReadOnly);
	QDomDocument doc;
	doc.setContent(&f, true);
	printf("%s", doc.toString().toLocal8Bit().data());
}
