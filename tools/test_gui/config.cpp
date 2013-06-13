#include "config.h"

#include <QProcess>
#include <QtXml>

#include <cassert>
#include <cstdio>

#define MARK "]]>]]>"
const QString netconfUri("urn:ietf:params:xml:ns:netconf:base:1.0");

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

		handleMessage(message);
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

void Config::handleMessage(const QByteArray &message) {
	QDomDocument xml;
	bool ok = xml.setContent(message);
	assert(ok);
	/*
	 * We don't check the namespace here. Qt seems to return empty string
	 * (I must be doing something wrong, obviously), and this is dirty
	 * test tool only anyway.
	 */
	const QString &name(xml.documentElement().tagName());
	if (name == "hello") {
		handleHello(xml);
		return;
	} else if (name == "rpc") {
		handleRpc(xml);
		return;
	}
	assert(false);
}

void Config::handleRpc(const QDomDocument &rpc) {

}

void Config::handleHello(const QDomDocument &) {
	connectButton->setEnabled(true);
	downloadButton->setEnabled(true);
	downloadButton->click();
}
