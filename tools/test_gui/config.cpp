#include "config.h"

#include <QProcess>

#include <cassert>
#include <cstdio>

#define MARK "]]>]]>"

Config::Config() :
	process(NULL)
{
	setupUi(this);
}

void Config::on_connectButton_clicked() {
	if (process) {
		disconnectNuci();
	} else {
		connectNuci();
	}
}

void Config::connectNuci() {
	incoming.clear();
	// Create and connect the process
	process = new QProcess(this);
	connect(process, SIGNAL(readyReadStandardOutput()), this, SLOT(data()));
	connect(process, SIGNAL(finished(int, QProcess::ExitStatus)), this, SLOT(terminated()));
	process->start(commandEdit->text());
	// Let it start
	process->waitForStarted(-1);
	// Push the <hello> message there.
	sendData("<?xml version='1.0' encoding='UTF-8'?><hello xmlns='urn:ietf:params:xml:ns:netconf:base:1.0'><capabilities><capability>urn:ietf:params:netconf:base:1.0</capability></capabilities></hello>");
	connectButton->setEnabled(false);
	connectButton->setText("Disconnect");
}

void Config::disconnectNuci() {

}

void Config::data() {
	// Some data arrived from remote
	incoming += process->readAll();
	int index;
	while ((index = incoming.indexOf(MARK)) != -1) {
		// Extract the message and drop it from the front
		QByteArray message(incoming.data(), index);
		incoming.remove(0, index + strlen(MARK));
		printf("Received XML:\n%s\n\n", message.data());


	}
}

void Config::terminated() {
	// The remote terminated
}

void Config::sendData(const QString &data) {
	QByteArray cp(data.toLocal8Bit());
	printf("Sending XML message:\n%s\n\n", cp.data());
	cp.append("\n" MARK);
	while (!cp.isEmpty())
		writeData(cp);
}

void Config::writeData(QByteArray &array) {
	qint64 written = process->write(array);
	assert(written > 0);
	array.remove(0, written);
}
